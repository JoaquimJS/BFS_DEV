create or replace
PACKAGE BODY "DO_BFS" IS 

/*------------------------------------------------------------------------------
--------------------------------------------------------------- DO_IMP_SP_AHV_NR
------------------------------------------------------------------------------*/
  PROCEDURE 
  DO_IMP_SP_AHV_NR ( mp_selektion_id IN INTEGER
                  , mp_out_result OUT INTEGER
                  , mp_datenimport_id IN INTEGER
                  , mp_standort_id IN INTEGER
                  , mp_data_context IN INTEGER) IS
                  
  sp_ahv_result INTEGER := 0;
  l_counter INTEGER ;

  BEGIN
      
      INSERT INTO dbg_test_bfs (SELEKTION_ID, sql_statement) VALUES (mp_selektion_id, 'start') ;
      
      FOR re IN (SELECT dossier_id FROM import_sec_selektion WHERE selektion_id = mp_selektion_id)
      LOOP

         DO_BFS.SP_AHV_NR(re.dossier_id, sp_ahv_result) ;
   
        IF (sp_ahv_result < 0) THEN 
          mp_out_result := -1 ; 
        END IF;
      
      END LOOP ;
      mp_out_result := 1 ; 
     
      INSERT INTO dbg_test_bfs (SELEKTION_ID, sql_statement) VALUES (mp_selektion_id, 'stop') ;
  
   EXCEPTION 
    WHEN NO_DATA_FOUND THEN
      mp_out_result := 0 ;
    --  RAISE;
    WHEN OTHERS THEN
      mp_out_result := -1 ;
      RAISE;
  
  END DO_IMP_SP_AHV_NR   ;             


/*------------------------------------------------------------------------------
---------------------------------------------------------------------- SP_AHV_NR
------------------------------------------------------------------------------*/

PROCEDURE SP_AHV_NR ( mp_doss_id IN INTEGER
                    , mp_out_result OUT INTEGER) IS


  TYPE               RT is RECORD (  
                       ahv_nummer           VARCHAR2(255)
                     , doss_id              INTEGER
                     , person_id            INTEGER
                     , person_type          VARCHAR2(3)
                     , nbr                  INTEGER
                     ) ;
                    
  
  TYPE                 RT_TABLE IS TABLE OF RT ;
  lc_rec               RT_TABLE ;

  p_query             VARCHAR2(4000) ;
  p_log               VARCHAR2(4000) ;
  
  l_err_code          INTEGER ;
  l_b_neubezueger     INTEGER := 0 ;
  
  c_imp_new_value     CONSTANT VARCHAR2(5) := '-3';
  c_plausimeldung_id  CONSTANT INTEGER := 201200 ;

BEGIN

      SELECT b_neubezuegerrecord INTO l_b_neubezueger FROM sh_dossier WHERE sh_dossier_id = mp_doss_id ;
      
      IF (l_b_neubezueger <> 0) THEN
    
          p_query := 'SELECT   t.versichertennummer ,
                               t.sh_dossier_id,
                               t.person_id ,
                               t.person_type,
                               t.nbr
                       FROM
                      (WITH subfact AS
                      (SELECT   versichertennummer,
                                sh_dossier_id ,
                                0     AS person_id,
                                ''ANT'' AS person_type
                         FROM   antragsteller
                        WHERE   versichertennummer NOT LIKE ''-%''
                      UNION
                       SELECT   versichertennummer,
                                sh_dossier_id ,
                                ue_person_id,
                                ''UE'' AS person_type
                         FROM   ue_person
                        WHERE   versichertennummer NOT LIKE ''-%''
                      UNION
                       SELECT   versichertennummer,
                                sh_dossier_id,
                                hh_person_id,
                                ''HH'' AS person_type
                         FROM   hh_person
                        WHERE   versichertennummer NOT LIKE ''-%''
                      )
                    SELECT  sh_dossier_id,
                            COUNT(*) over (partition BY versichertennummer) AS nbr ,
                            versichertennummer ,
                            person_id ,
                            person_type
                      FROM  subfact
                     WHERE  subfact.sh_dossier_id = '||mp_doss_id||'
                      ) t
                WHERE t.nbr > 1'; 
     
          BEGIN
            
              EXECUTE IMMEDIATE p_query BULK COLLECT INTO lc_rec ;
              
          EXCEPTION 
            WHEN NO_DATA_FOUND THEN 
              mp_out_result := 0 ; 
              --RAISE;
            WHEN OTHERS THEN 
              mp_out_result := -1 ;
              RAISE;
          END;
          
          BEGIN
              FOR i in 1..lc_rec.COUNT
              LOOP
                  
                    IF lc_rec(i).person_type = 'ANT' THEN 
                       p_query := 'UPDATE sec_antragsteller SET sec_antragsteller.versichertennummer = ''-3'' WHERE sh_dossier_id = '||mp_doss_id ; 
                    ELSIF lc_rec(i).person_type = 'UE' THEN 
                       p_query := 'UPDATE sec_ue_person SET sec_ue_person.versichertennummer = ''-3'' WHERE sh_dossier_id = '||mp_doss_id ||' AND sec_ue_person.ue_person_id = '||lc_rec(i).person_id ; 
                    ELSIF lc_rec(i).person_type = 'HH' THEN 
                       p_query := 'UPDATE sec_hh_person SET sec_hh_person.versichertennummer = ''-3'' WHERE sh_dossier_id = '||mp_doss_id ||' AND sec_hh_person.hh_person_id = '||lc_rec(i).person_id ; 
                    END IF ;
                   
                    p_log := 'INSERT INTO sh_dossier_imputation (sh_dossier_id, plausimeldung_id, alt_wert, neue_wert, befehl) 
                              VALUES ('||mp_doss_id||','||c_plausimeldung_id||','''||lc_rec(i).ahv_nummer||''', '''||c_imp_new_value||''', '''||replace(p_query, '''', '''''')||''')';
    
                   EXECUTE IMMEDIATE p_query ;
                   EXECUTE IMMEDIATE p_log ; 
                   COMMIT; 
       
              END LOOP;
              mp_out_result := 1;
    
          EXCEPTION
           WHEN OTHERS THEN 
                    mp_out_result := -1 ;
                    RAISE;
     
        END;  
    END IF;

END SP_AHV_NR ;





/*------------------------------------------------------------------------------
------------------------------------------------------------ SP_DADA_POST_PLAUSI
------------------------------------------------------------------------------*/


PROCEDURE 
SP_DADA_POST_PLAUSI ( mp_standort_id IN INTEGER DEFAULT 0
                    , mp_datenimport_id IN INTEGER DEFAULT 0
                    , mp_plausi_id IN INTEGER ) 
IS

     
    TYPE tbl_chr IS TABLE OF VARCHAR2(4000) ;
    TYPE tbl_int IS TABLE OF INTEGER ;
 
    lc_param1             tbl_int ;
    lc_param2             tbl_int ;
    lc_param3             tbl_int ;
    
    lc_sql_from           tbl_chr ;
    lc_sql_where          tbl_chr ;
    lc_sql_and            tbl_chr ;
    lc_leistungsfilter    tbl_chr ;
    lc_plausimeldung_id   tbl_int ;
    
    lc_standort_id        tbl_int ;
    lc_datenimport_id     tbl_int ;
    lc_jahr               tbl_int ;
    
    lc_doss_id            tbl_int;
    
    p_query_struct    VARCHAR2(4000) ;
    p_query_exec      VARCHAR2(4000) ;
    
    sql_from          v_plausi.from_bedingung%TYPE ;
    sql_where         v_plausi.where_bedingung%TYPE ;
    sql_and           v_plausi.and_bedingung%TYPE ;
    leistungsfilter   v_plausi.leistungsfilter%TYPE ;
    
    param1            v_plausimeldung.param1%TYPE ;
    param2            v_plausimeldung.param2%TYPE ;
    param3            v_plausimeldung.param3%TYPE ;
    
    plausimeldung_id  INTEGER ;
    l_count           INTEGER ;
    l_query           VARCHAR2(4000) ;
    l_query1          VARCHAR2(4000) ;
    l_query2          VARCHAR2(4000) ;
    l_err_code        INTEGER := 0 ;
    l_dt              DATE ;
    


    BEGIN <<MAIN_BLOC>>
       INSERT INTO dbg_test_bfs_dada (id, sql, rem, standort_id, datenimport_id, plausi_id) values (1 , 'START' , 'PROCEDURE SP_DADA_POST_PLAUSI', mp_standort_id, mp_datenimport_id, mp_plausi_id ) ;
    
    --EXECUTE IMMEDIATE 'ALTER SESSION SET NLS_LANGUAGE = ''FRENCH'' ' ;

       BEGIN <<BLOC_STRUCT_PLAUSI>>

          l_query1 := 'SELECT   p.from_bedingung
                              , p.where_bedingung
                              , p.and_bedingung
                              , p.leistungsfilter
                              , pm.param1
                              , pm.param2
                              , pm.param3
                              , pm.plausimeldung_id 
  
                        FROM    v_plausi p
                  INNER JOIN    v_plausimeldung pm
                          ON    p.plausi_id = pm.plausi_id
                       WHERE    p.plausi_id = '||mp_plausi_id ;
                       
                     
          EXECUTE IMMEDIATE l_query1 BULK COLLECT INTO lc_sql_from, lc_sql_where, lc_sql_and, lc_leistungsfilter, lc_param1, lc_param2, lc_param3, lc_plausimeldung_id ;
        
        EXCEPTION WHEN OTHERS THEN 
          RAISE ;
        
        END;
       
        BEGIN <<BLOC_VARIABLES_POURCENT>>
       
              l_query2 := 'SELECT   DISTINCT standort_id
                                  , soz_traeger_datenimport_id
                                  , jahr 
                            FROM    sh_dossier 
                            WHERE   standort_id IS NOT NULL
                                    AND soz_traeger_datenimport_id IS NOT NULL';
              
               IF (mp_standort_id <> 0) THEN 
                  l_query2 := l_query2 ||' AND standort_id = '||mp_standort_id ; 
               END IF;
               
               IF (mp_datenimport_id <> 0) THEN 
                  l_query2 := l_query2 ||' AND soz_traeger_datenimport_id = '||mp_datenimport_id ; 
               END IF;
            
            EXECUTE IMMEDIATE l_query2 BULK COLLECT INTO lc_standort_id, lc_datenimport_id, lc_jahr ;
        
        EXCEPTION WHEN OTHERS THEN 
          RAISE ;
        
        END ;
        
        
        /* Pemière boucle à partir de la première requête construite ci-dessus */ 
   
        FOR i IN 1..lc_plausimeldung_id.COUNT
        LOOP

          p_query_struct := 'SELECT     p.from_bedingung, p.where_bedingung, p.leistungsfilter, pm.param1, pm.param2, pm.param3, pm.plausimeldung_id
                               FROM     v_plausi p
                         INNER JOIN     v_plausimeldung pm
                                 ON     p.plausi_id = pm.plausi_id
                              WHERE     p_plausi_id = '||mp_plausi_id ;
                                  
          IF REGEXP_LIKE(lc_param1(i), '[0-9]{1,}') THEN 
              p_query_struct :=  p_query_struct||' AND pm.param1 = '||lc_param1(i) ;  
          END IF ; 
          
          IF REGEXP_LIKE(lc_param2(i), '[0-9]{1,}') THEN 
              p_query_struct :=  p_query_struct||' AND pm.param2 = '||lc_param2(i) ;  
          END IF ;                             
          
          IF REGEXP_LIKE(lc_param3(i), '[0-9]{1,}') THEN 
              p_query_struct :=  p_query_struct||' AND pm.param3 = '||lc_param3(i) ;  
          END IF ; 
                   
          BEGIN
          
            -- Construction de la requête          
            -- p_query_struct := 'SELECT COUNT(DISTINCT sh_dossier.sh_dossier_id) FROM '||lc_sql_from(i)||' WHERE '||lc_sql_where(i)||' '||lc_sql_and(i) ;
            
            p_query_struct := 'SELECT DISTINCT sh_dossier.sh_dossier_id FROM '||lc_sql_from(i)||' WHERE '||lc_sql_where(i)||' '||lc_sql_and(i) ;
            
            -- Remplacement des paramètres
            p_query_struct := replace (p_query_struct, ':param1', lc_param1(i)) ;
            p_query_struct := replace (p_query_struct, ':param2', lc_param2(i)) ;
            p_query_struct := replace (p_query_struct, ':param3', lc_param3(i)) ;

            /* Deuxième boucle sur la deuxième requête construite au début */
            
            -- Si la requête n'est pas vide, fait tourner la boucle
            IF (lc_datenimport_id.COUNT > 0) THEN
            
                FOR j IN 1..lc_datenimport_id.COUNT
                LOOP
                    -- On remplace les variables "%var%
                    p_query_exec := p_query_struct ;
                    
                    IF REGEXP_LIKE (p_query_exec, '(\%erhebungsjahr\%)') THEN
                        p_query_exec := REPLACE (p_query_exec, '%erhebungsjahr%', lc_jahr(j)) ;
                    ELSE
                        p_query_exec := p_query_exec ||' AND sh_dossier.jahr = '||lc_jahr(j);
                    END IF;
                    
                    IF REGEXP_LIKE (p_query_exec, '(\%standort_id\%)') THEN
                        p_query_exec := REPLACE (p_query_exec, '%standort_id%', lc_standort_id(j)) ;
                    ELSE
                        p_query_exec := p_query_exec ||' AND sh_dossier.standort_id = '||lc_standort_id(j);
                    END IF;
                    
                    IF REGEXP_LIKE (p_query_exec, '(\%datenimport_id\%)') THEN
                        p_query_exec := REPLACE (p_query_exec, '%datenimport_id%', lc_datenimport_id(j)) ;
                    ELSE
                        p_query_exec := p_query_exec ||' AND sh_dossier.soz_traeger_datenimport_id = '||lc_datenimport_id(j);
                    END IF;
                    
                    -- On doit également limiter la sélection au niveau des filtres de prestation.
                    p_query_exec := p_query_exec || ' AND  dossier_status_id <> 5 AND sh_dossier.sh_leistungstyp_id IN  (SELECT sh_leistungstyp_id FROM v_sh_leistungstyp 
                                    WHERE sh_leistungsfilter_id IN ('|| lc_leistungsfilter(i) ||'))' ;
                  
                    -- Remplacement des variables s.dossier_id
                    p_query_exec := REPLACE (p_query_exec, 's.dossier_id', 'sh_dossier.sh_dossier_id');
                    
                    -- Suppression des hints si besoin (en principe: non)
                    -- p_query_exec := REGEXP_REPLACE (p_query_exec, '(/\*\+(.)*\*/)', ' ') ;

                      BEGIN
                        EXECUTE IMMEDIATE p_query_exec BULK COLLECT INTO lc_doss_id ;
                        
                        FOR k IN 1..lc_doss_id.COUNT
                        LOOP
                          INSERT INTO sh_dossier_dada (plausimeldung_id, sh_dossier_id, soz_traeger_datenimport_id, standort_id) VALUES(lc_plausimeldung_id(i), lc_doss_id(k), lc_datenimport_id(j), lc_standort_id(j));
                         -- INSERT INTO dbg_test_bfs_2 values (lc_doss_id(k), p_query_exec, 'test GOL', null) ;
                      
                          INSERT INTO sh_dossier_dada_log (plausimeldung_id, sh_dossier_id, soz_traeger_datenimport_id, standort_id) VALUES(lc_plausimeldung_id(i), lc_doss_id(k), lc_datenimport_id(j), lc_standort_id(j));
                        
                        END LOOP;
                      
                      EXCEPTION WHEN OTHERS THEN
                        --dbms_output.put_line('Erreur récupération des dossiers : '||sqlerrm||' / query : '|| p_query_exec);
                        RAISE;
                   
                      END ;      
          
                  END LOOP ;
              END IF ;
            END;  
          END LOOP ; 

          UPDATE soz_traeger_datenimport 
             SET aufbereitungsphase_id = 22 
           WHERE soz_traeger_datenimport_id = mp_datenimport_id AND standort_id = mp_standort_id ;


          EXCEPTION /*dernier bloc*/
            WHEN OTHERS THEN 
                l_err_code := sqlcode ;
                INSERT INTO dbg_test_bfs_dada (id, sql, rem, standort_id, datenimport_id, plausi_id ) values (-1 , p_query_exec, l_err_code, mp_standort_id, mp_datenimport_id, mp_plausi_id ) ;
                IF (l_err_code = -1013) THEN 
                    RAISE ; -- arrêter l'exécution
                ELSE 
                    NULL;
                END IF;
 
     
END SP_DADA_POST_PLAUSI ;


/*------------------------------------------------------------------------------
--------------------------------------------------------- DO_SP_DADA_POST_PLAUSI
------------------------------------------------------------------------------*/

<<<<<<< HEAD
=======
/*
Voici un commentaire ajouté comme test pour GIT

Par exemple : il faudrait adapter le numéro de plausi.

Une deuxième modification.

Une troisième modification par un autre utilisateur (JoaquimJS)

*/
>>>>>>> master

PROCEDURE 
DO_SP_DADA_POST_PLAUSI (mp_datenimport_id IN INTEGER
                      , mp_standort_id IN INTEGER) IS

BEGIN

    DELETE FROM sh_dossier_dada 
          WHERE standort_id = mp_standort_id 
                AND soz_traeger_datenimport_id = mp_datenimport_id ;

    FOR re IN (SELECT plausi_id
                 FROM v_plausi
                WHERE plausi_id IN (    53,
                                        81,
                                        88,
                                        89,
                                        92,
                                        1060,
                                        1080,
                                        1100,
                                        1120,
                                        1122,
                                        1123,
                                        1140,
                                        1141,
                                        1160,
                                        1170,
                                        1310,
                                        1320,
                                        1321,
                                        1322,
                                        1323,
                                        1330,
                                        1380,
                                        1580,
                                        1861,
                                        2051,
                                        2070,
                                        2080,
                                        3121,
                                        3141,
                                        15004,
                                        15029,
                                        15065,
                                        15066,
                                        15068,
                                        15069,
                                        15070,
                                        15071,
                                        15115,
                                        15116,
                                        15117,
                                        15118,
                                        15119,
                                        16011,
                                        16012,
                                        16017,
                                        16070,
                                        16071,
                                        16090,
                                        16091,
                                        16110,
                                        16111,
                                        16120,
                                        16164,
                                        16165,
                                        16180,
                                        16181,
                                        16193,
                                        16270,
                                        16271,
                                        16320,
                                        16321,
                                        16330,
                                        16331,
                                     /* 100602,
                                        100603,
                                        100621,
                                        100623,
                                        100625,
                                        100627,*/
                                        200011,
                                        200030,
                                        200040,
                                        200050,
                                        200060,
                                        200070,
                                        200080,
                                        200200,
                                        200210,
                                        201000,
                                        201050,
                                        201060,
                                        201080

                                      ))
    LOOP
        BEGIN
        
          DO_BFS.SP_DADA_POST_PLAUSI ( mp_standort_id
                                     , mp_datenimport_id 
                                     , re.plausi_id  ) ;
        
        
         COMMIT;
        EXCEPTION 
          WHEN NO_DATA_FOUND THEN
            NULL;
          WHEN OTHERS THEN
            RAISE; 
            
        END;
    END LOOP ;

    EXCEPTION 
      WHEN NO_DATA_FOUND THEN
            NULL;
      WHEN OTHERS THEN
            RAISE; 
    
END DO_SP_DADA_POST_PLAUSI ;



/*------------------------------------------------------------------------------
-------------------------------------------------------------------- DO_DOSS_TYP
------------------------------------------------------------------------------*/



PROCEDURE DO_DOSS_TYP (mp_datenimport_id IN INTEGER, mp_standort_id IN INTEGER, mp_data_context INTEGER)
IS

    TYPE tbl_chr IS TABLE OF VARCHAR2(4000) ;
    TYPE tbl_int IS TABLE OF INTEGER ;
    TYPE tbl_dat IS TABLE OF DATE ;
 
    l_query                 VARCHAR2(4000) ;
    
    l_doss_id               tbl_int ;
    l_erste_auszahlung      tbl_dat ;
    l_letzte_zahlung        tbl_dat ;
    l_aufnahme              tbl_dat ;
    l_abgeschlossen         tbl_dat ;
    l_stichtag              tbl_int ;
    l_jahr                  tbl_int ;
    
    l_var_albv_1            tbl_dat ;
    l_var_albv_2            tbl_int ;
    l_var_albv_3            tbl_dat ;
    
    l_min_v1506             DATE ;
    l_max_v1602             DATE ;
    l_v1601                 NUMBER ;
    
    p_neubezug              NUMBER ;
    p_letztbezug            NUMBER ;
    p_doss_typ              NUMBER ;
    p_prev_ep               INTEGER ;
    
    
    

BEGIN

    ---------------------------------------------- Request 1 : dossiers NON-ALBV
    l_query := 'SELECT    sh_dossier_id
                        , dat_erste_auszahlung
                        , dat_letzte_zahlung
                        , dat_aufnahme 
                        , dat_abgeschlossen
                        , b_bezug_stichtag
                        , jahr
                  FROM    ROH_SH_DOSSIER 
                 WHERE    soz_traeger_datenimport_id = :x
                          AND standort_id = :y
                          AND b_neubezuegerrecord = 1
                          AND sh_leistungstyp_id <> 25'; 
                      
    EXECUTE IMMEDIATE l_query BULK COLLECT INTO   l_doss_id
                                                , l_erste_auszahlung
                                                , l_letzte_zahlung
                                                , l_aufnahme
                                                , l_abgeschlossen
                                                , l_stichtag 
                                                , l_jahr
                              USING mp_datenimport_id, mp_standort_id ;
    
    
    -------------------------------------------------------------------------
    -- Attribution du type de dossier
    -------------------------------------------------------------------------    
    
    FOR i IN 1..l_doss_id.COUNT LOOP

        p_prev_ep := l_jahr(i)-1 ;
        p_neubezug := -1 ;
        p_letztbezug := -1 ;
        p_doss_typ := -3 ;
       
        -- Critère de base : il FAUT une date de premier versement.
        IF ( l_erste_auszahlung(i) IS NOT NULL 
            AND l_letzte_zahlung(i) IS NOT NULL
            AND extract (year FROM l_erste_auszahlung(i)) < 9998) 
        THEN
            
            /* --- Calcul du "Neubezug" ----------------------------------------
               0  : Ancien dossier, premier versement avant la PE
               1  : Nouveau dossier, premier versement durant la PE
               -1 : Attribution impossible / code d'erreur pour l'attribution 
                    du type -3
            ------------------------------------------------------------------*/
            IF (extract (year FROM l_erste_auszahlung(i)) < l_jahr(i) ) THEN
              p_neubezug := 0 ;
            ELSIF (extract (year FROM l_erste_auszahlung(i)) >= l_jahr(i)) THEN
              p_neubezug := 1 ;
            ELSE
              p_neubezug := -1 ;
            END IF ;

            
            /* --- Calcul du "Letztbezug" ----------------------------------------
               0  : Dernier versement avant juillet de la PE-1 (dossier clos)
               1  : Dernier versement avant juillet de la PE (dossier en cours)
               2  : Dernier versement après juin de la PE (dossier non pris en compte)
               10 : Dernier versement après juin PE-1 (dossier clos)
               -1 : code d'erreur, attribution du doss_typ -3
            ------------------------------------------------------------------*/
            IF (l_letzte_zahlung(i) < TO_DATE('01.07'||p_prev_ep, 'DD.MM.RRRR')) THEN
              p_letztbezug := 0 ;
            ELSIF (l_letzte_zahlung(i) >= to_date('01.07'||p_prev_ep, 'DD.MM.RRRR') AND extract (year FROM l_letzte_zahlung(i)) = p_prev_ep) THEN
              p_letztbezug := 10 ;
            ELSIF (l_letzte_zahlung(i) < to_date('01.07'||l_jahr(i), 'DD.MM.RRRR') AND extract (year FROM l_letzte_zahlung(i)) = l_jahr(i)) THEN
              p_letztbezug := 1 ;
            
            ELSIF (l_letzte_zahlung(i) >= to_date('01.07'||l_jahr(i), 'DD.MM.RRRR') 
                   OR l_letzte_zahlung(i) = to_date('09.01.9999', 'DD.MM.RRRR')
                   OR l_letzte_zahlung(i) = to_date('08.01.9999', 'DD.MM.RRRR')
                   ) THEN
              p_letztbezug := 2 ;
            ELSE 
              p_letztbezug := -1 ;
            END IF ;
            

            /*------------------------------------------------------------------ 
            Règles de contrôles supplémentaires par rapport au concept de base
            
            Volontairement individualisées (ajout/suppression plus aisés)
            Si une règle est violée, elle attribue le doss_typ -3 en mettant 
            p_letztbezug à -1.
            ------------------------------------------------------------------*/
            dbms_output.put_line(extract (year from l_letzte_zahlung(i))); 
            
            IF (l_letzte_zahlung(i) < l_erste_auszahlung(i)) THEN 
                p_letztbezug := -1 ;
            END IF ;
            
            
            ---- Plausi 200060
            IF (l_letzte_zahlung(i) >= to_date('01.07'||l_jahr(i), 'DD.MM.RRRR') AND l_letzte_zahlung(i) < to_date('01.07'||l_jahr(i), 'DD.MM.RRRR')
                AND (l_stichtag(i) <> 2 OR extract (year from l_abgeschlossen(i)) = 9999)
                AND l_letzte_zahlung(i) < l_abgeschlossen(i)
                AND l_erste_auszahlung(i) <= l_letzte_zahlung(i)) 
            THEN
                p_letztbezug := -1 ;
            END IF;
            
          
            ---- Plausi 200080
            IF ( l_stichtag(i) = 1 AND l_letzte_zahlung(i) < to_date('01.12.'||l_jahr(i), 'DD.MM.RRRR')
                AND extract (year FROM l_letzte_zahlung(i)) < 9998 )
            THEN
                p_letztbezug := -1 ;
            END IF;
            
            
            IF ( extract (year FROM l_aufnahme(i)) < 9998 
                AND ((l_aufnahme(i) > l_abgeschlossen(i) )
                      OR l_aufnahme(i) > l_letzte_zahlung(i))) THEN
                 p_letztbezug := -1 ;
            END IF;   
            
          
            IF (extract (year FROM l_abgeschlossen(i)) < 9998 
                    AND ((l_abgeschlossen(i) < ADD_MONTHS(l_erste_auszahlung(i), 6) )
                          OR (l_abgeschlossen(i) < ADD_MONTHS(l_letzte_zahlung(i), 6)))) THEN
                p_letztbezug := -1 ;
            END IF;  
  
            IF (l_erste_auszahlung(i) < ADD_MONTHS(l_aufnahme(i), -1) 
                AND extract (year FROM l_erste_auszahlung(i)) < 9998) THEN
                p_letztbezug := -1 ;
            END IF; 
              
                  
       END IF ;     

       /* ----------------------------------------------------------------------
          Calcul du type de dossier en fonction des deux variables synthétiques
          Letztbezug et Neubezug.
          ------------------------------------------------------------------- */
       IF (p_neubezug >= 0 and p_letztbezug >= 0) THEN 
          
          IF (p_neubezug = 0 AND p_letztbezug = 1) THEN
              p_doss_typ := 2 ;
          ELSIF (p_neubezug = 0 AND p_letztbezug = 2) THEN
              p_doss_typ := 3 ;
          ELSIF (p_neubezug = 0 AND p_letztbezug = 0) THEN
              p_doss_typ := -3 ;
          ELSIF (p_neubezug = 0 AND p_letztbezug = 10) THEN
              p_doss_typ := 1 ;
          ELSIF (p_neubezug = 1 AND p_letztbezug = 1) THEN
              p_doss_typ := 4;
          ELSIF (p_neubezug = 1 AND p_letztbezug = 2) THEN
              p_doss_typ := 5;
          ELSE
              p_doss_typ := -3 ;
          END IF ;
       ELSE   
        p_doss_typ := -3 ;
       END IF ; 

       EXECUTE IMMEDIATE ('UPDATE ROH_SH_DOSSIER SET doss_typ = :x WHERE sh_dossier_id = :y') USING p_doss_typ, l_doss_id(i) ;
    
    END LOOP ;   
    ------------------------------------------ Fin attribution dossiers NON-ALBV
    COMMIT;
    
    
    ----------------------------------------------------------------------- ALBV
    
    FOR RE IN (SELECT   sh_dossier_id, jahr
                 FROM   roh_sh_dossier 
                WHERE   soz_traeger_datenimport_id = mp_datenimport_id
                        AND standort_id = mp_standort_id
                        AND sh_leistungstyp_id = 25
                        AND b_neubezuegerrecord = 1
                        )
    LOOP
    
        -- Reprise du concept du module SAS "module5A_WBSL"
        l_query := 'SELECT      var_ue_1
                              , var_ue_2
                              , var_ue_3 
                          
                      FROM   (

                            
                            SELECT      a.sh_dossier_id ,
                                        NULL                   AS ue_id ,
                                        a.dat_erste_auszahlung as var_ue_1 ,
                                        a.b_bezug_stichtag     as var_ue_2 ,
                                        a.dat_letzte_zahlung   as var_ue_3
                           
                              FROM      roh_antragsteller_albv a
                        INNER JOIN      roh_sh_dossier r 
                                ON      r.sh_dossier_id = a.sh_dossier_id
                                        AND r.jahr = '||re.jahr||'
            
                        UNION
                            
                            SELECT      u.sh_dossier_id ,
                                        u.ue_person_id         AS ue_id ,
                                        u.dat_erste_auszahlung as var_ue_1 ,
                                        u.b_bezug_stichtag     as var_ue_2 ,
                                        u.dat_letzte_zahlung   as var_ue_3
                        
                              FROM      roh_ue_person_albv u
                        INNER JOIN      roh_sh_dossier r 
                                ON      r.sh_dossier_id = u.sh_dossier_id
                                        AND r.jahr = '||re.jahr||'
                          ) t
                      
                      WHERE  t.sh_dossier_id =:x' ;
    
        EXECUTE IMMEDIATE l_query BULK COLLECT INTO  l_var_albv_1, l_var_albv_2, l_var_albv_3 USING   re.sh_dossier_id ;
        
        l_min_v1506 := to_date ('31.12.9999', 'DD.MM.RRRR') ;
        l_max_v1602 := to_date ('01.01.0001', 'DD.MM.RRRR') ;

        /*
        dbms_output.put_line('-----------------------------------------------') ;
        dbms_output.put_line('- dossier_id : '||re.sh_dossier_id) ;
        */
        
        FOR i in 1..l_var_albv_1.COUNT
        LOOP
        
           
            /*
            dbms_output.put_line('                                               ') ;
            dbms_output.put_line('Valeurs entrantes :                            ') ;
            dbms_output.put_line('- dat_erste_z ['||i||'] : '||l_var_albv_1(i)) ;
            dbms_output.put_line('- b_bezug_stichtag ['||i||'] : '||l_var_albv_2(i)) ;
            dbms_output.put_line('- dat_letzte_z ['||i||'] : '||l_var_albv_3(i)) ;
            */
           
            
            --- Transcription littérale des contrôles du module 5A
            
            --- "S1"
            IF (l_var_albv_1(i) = to_date ('04.01.9999', 'DD.MM.RRRR') 
                AND l_var_albv_2(i) = -4
                AND l_var_albv_3(i) = to_date ('04.01.9999', 'DD.MM.RRRR'))
            THEN
              l_var_albv_1(i) := to_date ('03.01.9999', 'DD.MM.RRRR') ;
              l_var_albv_2(i) := -3 ;
              l_var_albv_3(i) := to_date ('03.01.9999', 'DD.MM.RRRR') ;
            END IF ;
            
            IF (l_var_albv_1(i) = to_date ('08.01.9999', 'DD.MM.RRRR') 
                AND l_var_albv_2(i) = -8
                AND l_var_albv_3(i) = to_date ('08.01.9999', 'DD.MM.RRRR'))
            THEN
              l_var_albv_1(i) := to_date ('03.01.9999', 'DD.MM.RRRR') ;
              l_var_albv_2(i) := -3 ;
              l_var_albv_3(i) := to_date ('03.01.9999', 'DD.MM.RRRR') ;
            
            END IF ;
            
            --- "S2"
            IF (l_var_albv_2(i) = 1
                AND (
                  l_var_albv_3(i) = to_date ('08.01.9999', 'DD.MM.RRRR')
                  OR l_var_albv_3(i) = to_date ('09.01.9999', 'DD.MM.RRRR')))
            THEN
              l_var_albv_3(i) := to_date ('31.12.'||re.jahr, 'DD.MM.RRRR') ;
            END IF ;
            
            --- "S3"
            IF (l_var_albv_3(i) = to_date ('08.01.9999', 'DD.MM.RRRR')
                  OR l_var_albv_3(i) = to_date ('09.01.9999', 'DD.MM.RRRR'))
            THEN
              l_var_albv_3(i) :=  to_date ('03.01.9999', 'DD.MM.RRRR');
            END IF ;
            
            --- "S4"
            IF (l_var_albv_1(i) = to_date ('08.01.9999', 'DD.MM.RRRR'))
            THEN
              l_var_albv_1(i) := to_date ('03.01.9999', 'DD.MM.RRRR') ;
            END IF ;
            
            --- "S5"
            IF (l_var_albv_1(i) <> to_date ('09.01.9999', 'DD.MM.RRRR'))
            THEN
              IF ((EXTRACT (YEAR FROM l_var_albv_1(i)) < re.jahr - 40 ) 
                  OR (l_var_albv_1(i) > to_date ('31.12.'||re.jahr, 'DD.MM.RRRR')))
              THEN
                l_var_albv_1(i) := to_date ('03.01.9999', 'DD.MM.RRRR') ;
              END IF;
            END IF ;
            
            --- "S6"
             IF (l_var_albv_1(i) <> to_date ('03.01.9999', 'DD.MM.RRRR') 
                AND l_var_albv_2(i) = 1
                AND l_var_albv_3(i) > to_date ('31.12.'||re.jahr, 'DD.MM.RRRR'))
            THEN
              l_var_albv_3(i) := to_date ('31.12.'||re.jahr, 'DD.MM.RRRR') ;
            END IF ;
            
            IF (l_var_albv_1(i) <> to_date ('03.01.9999', 'DD.MM.RRRR') 
                AND l_var_albv_2(i) <> 1
                AND l_var_albv_3(i) > to_date ('31.12.'||re.jahr, 'DD.MM.RRRR'))
            THEN
              l_var_albv_3(i) := to_date ('03.01.9999', 'DD.MM.RRRR') ;
            END IF ;
            
            --- "S7"
            IF (l_var_albv_3(i) < to_date ('07.01.'||(re.jahr-1), 'DD.MM.RRRR'))
            THEN
              l_var_albv_3(i) := to_date ('03.01.9999', 'DD.MM.RRRR') ;
            END IF ;
            
            --- "S8"
            IF(l_var_albv_3(i) = to_date ('03.01.9999', 'DD.MM.RRRR'))
            THEN
              l_var_albv_2(i) := -3 ;
            END IF;
            
            IF(EXTRACT(YEAR FROM l_var_albv_3(i))= re.jahr 
               AND EXTRACT(MONTH FROM l_var_albv_3(i)) = 12)
            THEN
              l_var_albv_2(i) := 1 ;
            END IF;
            
            IF (l_var_albv_3(i) > to_date ('07.01.'||(re.jahr-1), 'DD.MM.RRRR')
                AND l_var_albv_3(i) < to_date ('01.12.'||(re.jahr), 'DD.MM.RRRR'))
            THEN
              l_var_albv_2(i) := 2 ;
            END IF ;

            --- Préaparation pour le calcul max/min
            IF (l_var_albv_1(i) = to_date ('03.01.9999', 'DD.MM.RRRR'))
            THEN
              l_var_albv_1(i) := null;
            END IF;

            IF (l_var_albv_3(i) = to_date ('03.01.9999', 'DD.MM.RRRR'))
            THEN
              l_var_albv_3(i) := null;
            END IF;
            
            
            -- Calcul min/max 
            IF (l_var_albv_1(i) IS NOT NULL 
                AND l_var_albv_1(i) < l_min_v1506 )
            THEN
              l_min_v1506 := l_var_albv_1(i) ;
            END IF;
            
            IF (l_var_albv_3(i) IS NOT NULL 
                AND l_var_albv_3(i) > l_max_v1602 )
            THEN
              l_max_v1602 := l_var_albv_3(i) ;
            END IF;
            
            l_v1601 := l_var_albv_2(1) ;
            
            
            /*
            dbms_output.put_line('                                               ') ;
            dbms_output.put_line('Valeurs sortantes :                            ') ;
            dbms_output.put_line('- dat_erste_z ['||i||'] : '||l_var_albv_1(i)) ;
            dbms_output.put_line('- b_bezug_stichtag ['||i||'] : '||l_var_albv_2(i)) ;
            dbms_output.put_line('- dat_letzte_z ['||i||'] : '||l_var_albv_3(i)) ;
            dbms_output.put_line('                                               ') ;
            */
            
            

        END LOOP ;
      
      
        IF (l_min_v1506 = to_date ('31.12.9999', 'DD.MM.RRRR')
            OR l_min_v1506 is NULL)
        THEN
          l_min_v1506 := to_date ('03.01.9999', 'DD.MM.RRRR') ;
        END IF;
        
         IF (l_max_v1602 = to_date ('01.01.0001', 'DD.MM.RRRR')
            OR l_max_v1602 is NULL)
        THEN
          l_max_v1602 := to_date ('03.01.9999', 'DD.MM.RRRR') ;
        END IF;
       
       
        ---- Calcul du type de dossier pour le dossier en cours dans la boucle
        
        ------------------
        --- LETZTBEZUG ---
        ------------------
        
        IF (EXTRACT(YEAR FROM l_max_v1602) = re.jahr-1 
            AND EXTRACT(MONTH FROM l_max_v1602) > 6) THEN 
          p_letztbezug := 10 ;
        
        ELSIF (EXTRACT(YEAR FROM l_max_v1602) = re.jahr-1 
            AND EXTRACT(MONTH FROM l_max_v1602) < 7) THEN
          p_letztbezug := 0 ;
          
        ELSIF (EXTRACT(YEAR FROM l_max_v1602) < re.jahr-1) THEN
          p_letztbezug := 0 ;
        
        ELSIF (EXTRACT(YEAR FROM l_max_v1602) = re.jahr
            AND EXTRACT(MONTH FROM l_max_v1602) < 7) THEN
          p_letztbezug := 1 ;
          
        ELSIF (EXTRACT(YEAR FROM l_max_v1602) = re.jahr
            AND EXTRACT(MONTH FROM l_max_v1602) > 6) THEN
          p_letztbezug := 2 ;
        
        ELSIF (EXTRACT(YEAR FROM l_max_v1602) = re.jahr+1) THEN
          p_letztbezug := 2 ;
          
        ELSIF (l_max_v1602 = to_date ('08.01.9999', 'DD.MM.RRRR')) THEN
          p_letztbezug := 2 ;
        
        ELSIF (l_max_v1602 = to_date ('03.01.9999', 'DD.MM.RRRR')) THEN
          p_letztbezug := -3 ; 
          
        ELSE
          p_letztbezug := -3 ;
      
        END IF ;
        
        IF (p_letztbezug = -3 AND l_v1601 = 1) THEN
          p_letztbezug := 2 ;
        END IF;
        
        
        ----------------
        --- NEUBEZUG ---
        ----------------
         IF (extract (year FROM l_min_v1506) < re.jahr ) THEN
              p_neubezug := 0 ;
         ELSIF (extract (year FROM l_min_v1506) >= re.jahr 
                AND extract (year FROM l_min_v1506) < re.jahr+2 ) THEN
              p_neubezug := 1 ;
         ELSE
              p_neubezug := -3 ;
         END IF ;
         
        -- Attribution du type : 
        IF p_letztbezug in (0,10)  AND p_neubezug IN (0,-3) THEN 
          p_doss_typ := 1;
	  		
        ELSIF p_letztbezug = 1  AND p_neubezug IN (0,-3) THEN 
          p_doss_typ := 2;
	  		
        ELSIF p_letztbezug = 2  AND p_neubezug IN (0,-3) THEN 
          p_doss_typ := 3;
	  		
        ELSIF p_letztbezug = 1  AND p_neubezug =  1 THEN 
          p_doss_typ := 4;
	  		
        ELSIF p_letztbezug = 2  AND p_neubezug =  1 THEN 
          p_doss_typ := 5;
	  		
        ELSIF p_letztbezug = -3  AND p_neubezug = 0 THEN 
          p_doss_typ := -3;
        
        ELSIF p_letztbezug = -3  AND p_neubezug = 1 THEN 
          p_doss_typ := -3;
	  		
        ELSIF p_letztbezug = -3  AND p_neubezug = -3 THEN 
          p_doss_typ := -3;
	   		
        ELSE p_doss_typ := -3;
        END IF ;

        /*
        dbms_output.put_line('                                               ') ;
        dbms_output.put_line('Valeurs finales :                            ') ;
        dbms_output.put_line('- l_max_v1602  : '||l_max_v1602) ;
        dbms_output.put_line('- l_min_v1506  : '||l_min_v1506) ;
        dbms_output.put_line('- p_letztbezug  : '||p_letztbezug) ;
        dbms_output.put_line('- p_neubezug  : '||p_neubezug) ;
        dbms_output.put_line('- doss_typ : '||p_doss_typ) ;
        dbms_output.put_line('************************************************ ');                                  
        */
        
        
        EXECUTE IMMEDIATE ('UPDATE ROH_SH_DOSSIER SET doss_typ = :x WHERE sh_dossier_id = :y') USING p_doss_typ, re.sh_dossier_id ;
       
        
    END LOOP ;
 
    COMMIT;
 
EXCEPTION WHEN OTHERS THEN 
  RAISE ;


END DO_DOSS_TYP ;




END DO_BFS;