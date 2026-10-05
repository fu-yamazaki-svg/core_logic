-- 01_01_daily_update_kpi3.v196
    -- 更新日：2026/07/17
    -- 作業者：細江
    -- 更新内容：タイムアウト（DEADLINE_EXCEEDED）エラーに伴うリファクタリング

--テーブル検索用
-- marketing_edit_v2.01_01_career_const_account_job_seeker_accumulated
-- marketing_edit_v2.01_02_entrance_edit_accumulated
-- marketing_edit_v2.01_04_01_record_preprocessed
-- marketing_edit_v2.01_04_02_record_preprocessed
-- marketing_edit_v2.01_10_01_reregistration_rank
-- marketing_edit_v2.01_11_01_nu_rank
-- marketing_edit_v2.01_05_01_record_raw
-- marketing_edit_v2.02_01_career_const_action_aggregated
-- marketing_edit_v2.03_01_career_contract_raw
-- marketing_edit_v2.03_02_const_contract_raw
-- marketing_edit_v2.01_05_02_record_raw
-- marketing_edit_v2.03_03_career_contract_processed
-- marketing_edit_v2.03_04_const_contract_processed
-- marketing_edit_v2.01_06_01_before_daily_share
-- marketing_edit_v2.01_06_02_before_daily_share
-- marketing_edit_v2.01_07_before_entrance_analysis
-- marketing_edit_v2.01_09_01_before_exit_action_calc
-- marketing_edit_v2.01_09_02_before_exit_route_judged
-- marketing_edit_v2.01_09_03_before_exit_analysis
--テーブル検索用



/*
★★★★★★★★★★★★★★★★★★★★データマート編集者は必ず確認下さい★★★★★★★★★★★★★★★★★★★★
    ○ 本データマートにより集計される数値により当社の意思決定(広告運用、投資判断、IR用情報等)が行われていることに十分留意ください、現場向けcsvファイル用数値や経営企画部作成の取締役会資料のソースとして引用されているため、基本的に出力結果が変わる形でのクエリ変更は出来ません
        →変更する場合は関係各所と過不足無く連携して対応すること
    ○ ロジックの概要は下記に説明されています
         https://trytgroup.sharepoint.com/:x:/s/marketing/ESi61nxQHyJNks75qjTa4EoBhZ4NFJYKgJTOe2k4DChzgg?e=3S7a8R
    ○ 2025/7/11 より"snap_shot_master"からの引用を停止し、「接触日」が25年7月以降のレコードについては、accumulated(更新差分テーブル)からの引用に変更(運用保守の効率化およびクエリ実行コスト削減のため)
    ○ 本データマートは21年頃の構築分をリファクタリングしたものであるが、簡略化して再設計しようとする場合、以下により「流入経路」毎の値が変動してしまうため、基本的に設計を変更することは出来ない(250130 KI追記)
        A) 当初のKPI管理運用は2020年頃にコンサル会社のリヴァンプ社によりエクセルファイルで行われており、以後BQに移行してKPI管理が行われることになったが、当時の管理手法が踏襲されており独特の方法でJOINや条件分岐が行われているため(ExcelファイルをBQ上で表現しているだけ)
        B) 当社のSalesForceのオブジェクトは体系的に開発されてきたとはいえず煩雑な構造になっており、「流入経路」を含めた集計用項目はアドホックに引用するしかないため
    ○ 新規に項目追加が生じた場合は、tryt-bigquery-pj.production_tryt_informatica.XXX_accumulated のテーブルにおいても項目を追加すること
    ○ 現場担当者が参照しているタブローや「ローデータ」(tryt-bigquery-pj.marketing_output_v2.01_digital_marketing_dailyから出力される)に異常があると連絡を受けた場合は下記を確認すること
        1 SF→BQのETLツールを用いたデータ連携の確認(インシデントが仮に発生した際は、全体の数値が更新されない等明らかに特定でき、かつDX推進部から連絡が来るので通常スキップで構わない)
        2 スケジュールクエリにエラーが出ていないかの確認
        3 各種マスタに問題が無いかの確認
        4 求職者OBJ(career_account_job_seeker)における「utm情報」や「担当拠点」の値の確認
        5 データマート編集者によるクエリの記述やタブローの関数の確認(仮に誤った記述のままスケジュール化やBIをパブリッシュした場合、現場担当者より直ぐに連絡が来るため、これが原因であることは殆ど無い)
*/


-- 集計対象レコード（バッチ実行日から起算して過去５年分）の開始日を予め宣言
DECLARE target_start_date DATE DEFAULT DATE_TRUNC(DATE_SUB(CURRENT_DATE('Asia/Tokyo'), INTERVAL 4 YEAR), YEAR);


-- marketing_edit_v2.01_01_career_const_account_job_seeker_accumulated
    -- 更新日：2026/07/17
    -- 作業者：細江
    -- 更新内容：タイムアウト（DEADLINE_EXCEEDED）エラーに伴うリファクタリング

/*
■実行内容
career/const_account_job_seekerにおけるKPI集計に必要な項目を抽出し1つのテーブルにユニオンする
(PK:cd__c)
*/

CREATE OR REPLACE TABLE `tryt-bigquery-pj.marketing_edit_v2.01_01_career_const_account_job_seeker_accumulated` PARTITION BY run_date AS 
WITH 
    career_account_job_seeker AS ( -- career_account_job_seekerからの項目引用
        SELECT
            -- career/const 共通 --
             t1.id AS jsid                                                          -- 求職者ID
            , t1.cd__c                                                              -- SFID
            , DATE(t1.registration_date__c) AS registration_date__c                 -- 登録日
            , DATE(t1.saitourokubi_adkeiyu__c) AS saitourokubi_adkeiyu__c           -- 再登録日（広告経由） ※marketing_edit_v2.01_00_career_account_job_seeker_temp_fieldにてウェルクス用項目と比較し新しい日付を引用
            , DATE(t1.saitourokubiseokeiyu__c) AS saitourokubiseokeiyu__c           -- 再登録日（SEO経由） ※marketing_edit_v2.01_00_career_account_job_seeker_temp_fieldにてウェルクス用項目と比較し新しい日付を引用
            , DATE(t1.saitourokubisyukeiyou__c) AS saitourokubisyukeiyou__c         -- 再登録日（CRM経由） ※marketing_edit_v2.01_00_career_account_job_seeker_temp_fieldにてウェルクス用項目と比較し新しい日付を引用
            , t1.first_hearing__c AS dummy_step1_from_js                            -- コンタクト履歴において欠損している各ステップ毎の日付を補正する対応を後続のクエリで実行用
            , t1.job_suggestion__c AS dummy_step2_from_js                           -- コンタクト履歴において欠損している各ステップ毎の日付を補正する対応を後続のクエリで実行用
            , t1.determination_of_interview_date__c AS dummy_step3_from_js          -- コンタクト履歴において欠損している各ステップ毎の日付を補正する対応を後続のクエリで実行用
            , t1.interview_implementation__c AS dummy_step4_from_js                 -- コンタクト履歴において欠損している各ステップ毎の日付を補正する対応を後続のクエリで実行用
            , t1.agreement__c AS dummy_step5_from_js                                -- コンタクト履歴において欠損している各ステップ毎の日付を補正する対応を後続のクエリで実行用
            , t1.billing_state                                                      -- 都道府県
            , t1.branch_text__c                                                     -- 担当拠点（テキスト）★★★【重要】Branch__cでは無いのでSalesForce担当者と連携する場合は要注意★★★
            , t1.department_in_charge__c                                            -- 担当部署
            , t2.name                                                               -- 氏名 -- 担当CA名
            , t1.owner_id                                                           -- 担当者 -- 担当CAのID
            , t1.status__c                                                          -- ステータス
            , t1.referral_status__c                                                 -- 紹介ステータス
            , t1.deletion_hope_reason__c                                            -- 削除希望理由
            , t1.web_changehopetime__c                                              -- 【希望】登録時_希望時期
            , t1.utmsource__c AS utmsource__c_not_first                             -- utm_source ★★初回登録時の情報ではないため、便宜的に名称を変更している★★
            , t1.utmmedium__c AS utmmedium__c_not_first                             -- utm_medium ★★初回登録時の情報ではないため、便宜的に名称を変更している★★
            , t1.utmcampaign__c                                                     -- utm_campaign
            , t1.utmcontent__c                                                      -- utm_content
            , t1.utmterm__c                                                         -- utm_term
            , t1.reregisterutmsource__c                                             -- 再登録utm_source
            , t1.reregisterutmmedium__c                                             -- 再登録utm_medium
            , t1.reregisterutmcampaign__c                                           -- 再登録utm_campaign
            , t1.reregisterutmcontent__c                                            -- 再登録utm_content
            , t1.reregisterutmterm__c                                               -- 再登録utm_term
            , t1.gclid__c                                                           -- gclid
            , t1.inflow_route__c                                                    -- 流入経路
            , t1.reregister_inflow_route__c                                         -- 再登録流入経路            
            
            -- careerのみ --
            , DATE(t1.saitourokubigaibukeiyu__c) AS saitourokubigaibukeiyu__c       -- 再登録日（外部媒体経由）
            , t1.registration_route_fisrst_navi_kaigo__c                            -- 登録経路（ファーストナビ_介護）
            , t1.registration_route_kyuzinzyanal__c                                 -- 登録経路（求人ジャーナル）
            , t1.registration_route_nursing__c                                      -- 登録経路（介護WORKER）
            , t1.registration_routekaigolila__c                                     -- 登録経路（介護リラ）
            , CASE 
                WHEN t3.registration_route_owned_media__c = 'ケア求人ナビ' THEN 1 
                ELSE 0 
            END AS registration_route_care_job_navi__c                              -- 登録経路（ケア求人ナビ）
            , t1.registration_route_fisrst_navi__c                                  -- 登録経路（ファーストナビ_看護）
            , t1.registrationroutenurse_e__c                                        -- 登録経路（ナースエージェント）
            , t1.registration_route_nurse__c                                        -- 登録経路（ナースワーカー）
            , t1.registration_routenasusenka__c                                     -- 登録経路（ナース専科）
            , CASE 
                WHEN t3.registration_route_owned_media__c = '保育士求人ナビ' THEN 1 
                ELSE 0 
            END AS registration_route_childcare_job_navi__c                         -- 登録経路（保育士求人ナビ）
            , t1.registration_routelisujobs__c                                      -- 登録経路（リスジョブ）
            , t1.registration_route_medridgechildcares__c                           -- 登録経路（メドリッジ）
            , t1.registration_route_nikkei_medicals__c                              -- 登録経路（日経メディカルキャリア）
            , t1.nurseryteachermikata__c                                            -- 登録経路（保育士のミカタ）
            , t1.registration_route_hoikunooshigoto__c                              -- 登録経路（保育のお仕事）
            , t1.registration_route_eiyoshinooshigoto__c                            -- 登録経路（栄養士のお仕事）
            , t1.registration_route_friend__c                                       -- 登録経路（友人紹介）
            , t1.registration_route_trytworker__c                                   -- 登録経路（トライトワーカー）
            , t3.registration_route_crm__c                                          -- 登録経路（CRM経由）
            , t1.registration_routeyakukyari__c                                     -- 登録経路（薬キャリ） 20250115追加
            , t1.age__c                                                             -- 年齢
            , t1.yuusensikakusyuukeiyou__c                                          -- 優先資格(集計）
            , t1.kiboukinmukeitaisyuukei__c                                         -- 希望勤務形態(集計)
            , t1.employment_type_shift_pattern1__c                                  -- 【希望】雇用形態1
            , t1.affiliate_approval_key__c                                          -- アフィリエイト承認key
            , t1.utmsource_first__c                                                 -- utm_source(初回)
            , t1.utmmedium_first__c                                                 -- utm_medium(初回)
            , t1.reregistre_web_requirements__c                                     -- web用再登録転職希望時期
            , t1.reregistre_web_changehopetime__c                                   -- web用再登録希望勤務形態
            , t1.web_job_application_number__c                                      -- web登録時応募求人番号
            , t1.job_change_time_from__c                                            -- 転職希望時期FROM
            , t1.registeredoccupation__pc                                           -- 登録職種 ※20241111追加
            , t3.import_type__c                                                     -- 取り込み種別
            , t3.registration_route_owned_media__c                                  -- 登録経路（自社メディア）
            , t3.registration_route_external_site__c                                -- 登録経路（保育isお仕事） ※20241111追加
            
            -- constのみ --
            , CAST(NULL AS STRING) AS registration_route01__c
            , CAST(NULL AS STRING) AS registration_route02__c
            , CAST(NULL AS STRING) AS desired_industry__c
            , CAST(NULL AS STRING) AS age_group__c
            , CAST(NULL AS STRING) AS desired_occupation__c
            , CAST(NULL AS INT64) AS experience_in_construction_management__c
            , CAST(NULL AS INT64) AS field_supervisor_experience__c
            
            , t1.followupchangeddate__c                                             -- NU対象変更日 ※250711追加
            , t1.person_contact_id                                                  -- 施設担当者 ID ※250711追加
            , t1.last_modified_date                                                 -- 最終更新日 ※250711追加
            , CURRENT_DATE("Asia/Tokyo") AS run_date                                -- バッチ実行日
        FROM `tryt-bigquery-pj.marketing_edit_v2.01_00_career_account_job_seeker_temp_field` AS t1
        LEFT JOIN `tryt-bigquery-pj.production_tryt_informatica.career_user` AS t2
            ON t1.owner_id = t2.id -- 求職者とユーザの紐づけ
        LEFT JOIN `tryt-bigquery-pj.marketing_edit_v2.02_00_career_contact_temp_field` AS t3
            ON t1.person_contact_id = t3.id -- 求職者と施設担当者の紐づけ
        WHERE 
            (
                ( t1.careersupport__c IS NULL OR t1.careersupport__c = 'する') -- 転職サポート
                    AND (t1.registered_mail_title__c IS NULL OR t1.registered_mail_title__c NOT LIKE '%大会チラシ%') --2018年頃の不明な集客による登録は除外
                    AND 
                        (
                            t1.registration_date__c >= target_start_date           -- 登録日
                            OR t1.saitourokubi_adkeiyu__c >= target_start_date     -- 再登録日（広告経由）
                            OR t1.saitourokubigaibukeiyu__c >= target_start_date   -- 再登録日（外部媒体経由）
                            OR t1.saitourokubiseokeiyu__c >= target_start_date     -- 再登録日（SEO経由）
                            OR t1.saitourokubisyukeiyou__c >= target_start_date    -- 再登録日（CRM経由）
                        )
            ) 
            OR t1.followupchangeddate__c >= target_start_date -- NU対象変更日
    ),
    
    career_account_job_seeker_accumulated AS ( -- career_account_job_seekerからの項目引用
        SELECT
            -- career/const 共通 --
            t1.id AS jsid                                                           -- 求職者ID
            , t1.cd__c                                                              -- SFID
            , DATE(t1.registration_date__c) AS registration_date__c                 -- 登録日
            , DATE(t1.saitourokubi_adkeiyu__c) AS saitourokubi_adkeiyu__c           -- 再登録日（広告経由） ※marketing_edit_v2.01_00_career_account_job_seeker_temp_fieldにてウェルクス用項目と比較し新しい日付を引用
            , DATE(t1.saitourokubiseokeiyu__c) AS saitourokubiseokeiyu__c           -- 再登録日（SEO経由） ※marketing_edit_v2.01_00_career_account_job_seeker_temp_fieldにてウェルクス用項目と比較し新しい日付を引用
            , DATE(t1.saitourokubisyukeiyou__c) AS saitourokubisyukeiyou__c         -- 再登録日（CRM経由） ※marketing_edit_v2.01_00_career_account_job_seeker_temp_fieldにてウェルクス用項目と比較し新しい日付を引用
            , t1.first_hearing__c AS dummy_step1_from_js                            -- コンタクト履歴において欠損している各ステップ毎の日付を補正する対応を後続のクエリで実行用
            , t1.job_suggestion__c AS dummy_step2_from_js                           -- コンタクト履歴において欠損している各ステップ毎の日付を補正する対応を後続のクエリで実行用
            , t1.determination_of_interview_date__c AS dummy_step3_from_js          -- コンタクト履歴において欠損している各ステップ毎の日付を補正する対応を後続のクエリで実行用
            , t1.interview_implementation__c AS dummy_step4_from_js                 -- コンタクト履歴において欠損している各ステップ毎の日付を補正する対応を後続のクエリで実行用
            , t1.agreement__c AS dummy_step5_from_js                                -- コンタクト履歴において欠損している各ステップ毎の日付を補正する対応を後続のクエリで実行用
            , t1.billing_state                                                      -- 都道府県
            , t1.branch_text__c                                                     -- 担当拠点（テキスト）★★★【重要】Branch__cでは無いのでSalesForce担当者と連携する場合は要注意★★★
            , t1.department_in_charge__c                                            -- 担当部署
            , t2.name                                                               -- 氏名 -- 担当CA名
            , t1.owner_id                                                           -- 担当者 -- 担当CAのID
            , t1.status__c                                                          -- ステータス
            , t1.referral_status__c                                                 -- 紹介ステータス
            , t1.deletion_hope_reason__c                                            -- 削除希望理由
            , t1.web_changehopetime__c                                              -- 【希望】登録時_希望時期
            , t1.utmsource__c AS utmsource__c_not_first                             -- utm_source ★★初回登録時の情報ではないため、便宜的に名称を変更している★★
            , t1.utmmedium__c AS utmmedium__c_not_first                             -- utm_medium ★★初回登録時の情報ではないため、便宜的に名称を変更している★★
            , t1.utmcampaign__c                                                     -- utm_campaign
            , t1.utmcontent__c                                                      -- utm_content
            , t1.utmterm__c                                                         -- utm_term
            , t1.reregisterutmsource__c                                             -- 再登録utm_source
            , t1.reregisterutmmedium__c                                             -- 再登録utm_medium
            , t1.reregisterutmcampaign__c                                           -- 再登録utm_campaign
            , t1.reregisterutmcontent__c                                            -- 再登録utm_content
            , t1.reregisterutmterm__c                                               -- 再登録utm_term
            , t1.gclid__c                                                           -- gclid
            , t1.inflow_route__c                                                    -- 流入経路
            , t1.reregister_inflow_route__c                                         -- 再登録流入経路            
            
            -- careerのみ --
            , DATE(t1.saitourokubigaibukeiyu__c) AS saitourokubigaibukeiyu__c       -- 再登録日（外部媒体経由）
            , t1.registration_route_fisrst_navi_kaigo__c                            -- 登録経路（ファーストナビ_介護）
            , t1.registration_route_kyuzinzyanal__c                                 -- 登録経路（求人ジャーナル）
            , t1.registration_route_nursing__c                                      -- 登録経路（介護WORKER）
            , t1.registration_routekaigolila__c                                     -- 登録経路（介護リラ）
            , CASE 
                WHEN t3.registration_route_owned_media__c = 'ケア求人ナビ' THEN 1 
                ELSE 0 
            END AS registration_route_care_job_navi__c                              -- 登録経路（ケア求人ナビ）
            , t1.registration_route_fisrst_navi__c                                  -- 登録経路（ファーストナビ_看護）
            , t1.registrationroutenurse_e__c                                        -- 登録経路（ナースエージェント）
            , t1.registration_route_nurse__c                                        -- 登録経路（ナースワーカー）
            , t1.registration_routenasusenka__c                                     -- 登録経路（ナース専科）
            , CASE 
                WHEN t3.registration_route_owned_media__c = '保育士求人ナビ' THEN 1 
                ELSE 0 
            END AS registration_route_childcare_job_navi__c                         -- 登録経路（保育士求人ナビ）
            , t1.registration_routelisujobs__c                                      -- 登録経路（リスジョブ）
            , t1.registration_route_medridgechildcares__c                           -- 登録経路（メドリッジ）
            , t1.registration_route_nikkei_medicals__c                              -- 登録経路（日経メディカルキャリア）
            , t1.nurseryteachermikata__c                                            -- 登録経路（保育士のミカタ）
            , t1.registration_route_hoikunooshigoto__c                              -- 登録経路（保育のお仕事）
            , t1.registration_route_eiyoshinooshigoto__c                            -- 登録経路（栄養士のお仕事）
            , t1.registration_route_friend__c                                       -- 登録経路（友人紹介）
            , t1.registration_route_trytworker__c                                   -- 登録経路（トライトワーカー）
            , t3.registration_route_crm__c                                          -- 登録経路（CRM経由）
            , t1.registration_routeyakukyari__c                                     -- 登録経路（薬キャリ） 20250115追加
            , t1.age__c                                                             -- 年齢
            , t1.yuusensikakusyuukeiyou__c                                          -- 優先資格(集計）
            , t1.kiboukinmukeitaisyuukei__c                                         -- 希望勤務形態(集計)
            , t1.employment_type_shift_pattern1__c                                  -- 【希望】雇用形態1
            , t1.affiliate_approval_key__c                                          -- アフィリエイト承認key
            , t1.utmsource_first__c                                                 -- utm_source(初回)
            , t1.utmmedium_first__c                                                 -- utm_medium(初回)
            , t1.reregistre_web_requirements__c                                     -- web用再登録転職希望時期
            , t1.reregistre_web_changehopetime__c                                   -- web用再登録希望勤務形態
            , t1.web_job_application_number__c                                      -- web登録時応募求人番号
            , t1.job_change_time_from__c                                            -- 転職希望時期FROM
            , t1.registeredoccupation__pc                                           -- 登録職種 ※20241111追加
            , t3.import_type__c                                                     -- 取り込み種別
            , t3.registration_route_owned_media__c                                  -- 登録経路（自社メディア）
            , t3.registration_route_external_site__c                                -- 登録経路（保育isお仕事） ※20241111追加
            
            -- constのみ --
            , CAST(NULL AS STRING) AS registration_route01__c
            , CAST(NULL AS STRING) AS registration_route02__c
            , CAST(NULL AS STRING) AS desired_industry__c
            , CAST(NULL AS STRING) AS age_group__c
            , CAST(NULL AS STRING) AS desired_occupation__c
            , CAST(NULL AS INT64) AS experience_in_construction_management__c
            , CAST(NULL AS INT64) AS field_supervisor_experience__c
            
            , t1.followupchangeddate__c                                             -- NU対象変更日 ※250711追加
            , t1.person_contact_id                                                  -- 施設担当者 ID ※250711追加
            , t1.last_modified_date                                                 -- 最終更新日 ※250711追加
            , t1.run_date                                                           -- バッチ実行日
        FROM 
            (
                SELECT 
                    *
                    ,ROW_NUMBER()OVER(ORDER BY id, run_date, created_date, last_modified_date) AS temp_id
                FROM `tryt-bigquery-pj.marketing_edit_v2.01_00_career_account_job_seeker_accumulated_temp_field`
            ) AS t1
        LEFT JOIN `tryt-bigquery-pj.production_tryt_informatica.career_user` AS t2
            ON t1.owner_id = t2.id -- 求職者とユーザの紐づけ
        LEFT JOIN `tryt-bigquery-pj.marketing_edit_v2.02_00_career_contact_accumulated_temp_field` AS t3
            ON t1.person_contact_id = t3.id -- 求職者と施設担当者の紐づけ
                AND t1.run_date >= t3.run_date
        WHERE 
            (
                ( t1.careersupport__c IS NULL OR t1.careersupport__c = 'する') -- 転職サポート
                    AND (t1.registered_mail_title__c IS NULL OR t1.registered_mail_title__c NOT LIKE '%大会チラシ%') --2018年頃の不明な集客による登録は除外
                    AND 
                        (
                            t1.registration_date__c >= target_start_date           -- 登録日
                            OR t1.saitourokubi_adkeiyu__c >= target_start_date     -- 再登録日（広告経由）
                            OR t1.saitourokubigaibukeiyu__c >= target_start_date   -- 再登録日（外部媒体経由）
                            OR t1.saitourokubiseokeiyu__c >= target_start_date     -- 再登録日（SEO経由）
                            OR t1.saitourokubisyukeiyou__c >= target_start_date    -- 再登録日（CRM経由）
                        )
            ) 
            OR t1.followupchangeddate__c >= target_start_date -- NU対象変更日
        QUALIFY
            ROW_NUMBER()OVER(PARTITION BY t1.temp_id ORDER BY t3.run_date DESC, t3.last_modified_date DESC) = 1
        ),
    
    career_account_job_seeker_all AS ( -- job_seekerの積み上げテーブル（accumulated）と最新のjob_seekerをユニオン
        SELECT * FROM career_account_job_seeker
        UNION ALL
        SELECT * FROM career_account_job_seeker_accumulated
        ),
    
    const_account_job_seeker AS ( -- const_account_job_seekerからの引用
        SELECT
            -- career/const共通 --
            t1.id AS jsid                                                           -- 求職者ID
            , t1.cd__c                                                              -- SFID
            , DATE(t1.registration_date__c) AS registration_date__c                 -- 登録日
            , DATE(t1.saitourokubi_adkeiyu__c) AS saitourokubi_adkeiyu__c           -- 再登録日（重複）-- 再登録日（広告経由）と同義
            , DATE(t1.saitourokubiseokeiyu__c) AS saitourokubiseokeiyu__c           -- 再登録日（SEO経由）
            , DATE(t1.saitourokubisyukeiyou__c) AS saitourokubisyukeiyou__c         -- 再登録日（CRM経由）
            , DATE(t1.neg_stat_date03__c) AS dummy_step1_from_js                    -- コンタクト履歴において欠損している各ステップ毎の日付を補正する対応を後続のクエリで実行用
            , DATE(t1.neg_stat_date05__c) AS dummy_step2_from_js                    -- コンタクト履歴において欠損している各ステップ毎の日付を補正する対応を後続のクエリで実行用
            , DATE(t1.neg_stat_date08__c) AS dummy_step3_from_js                    -- コンタクト履歴において欠損している各ステップ毎の日付を補正する対応を後続のクエリで実行用
            , DATE(t1.neg_stat_date11__c) AS dummy_step4_from_js                    -- コンタクト履歴において欠損している各ステップ毎の日付を補正する対応を後続のクエリで実行用
            , DATE(t1.neg_stat_date14__c) AS dummy_step5_from_js                    -- コンタクト履歴において欠損している各ステップ毎の日付を補正する対応を後続のクエリで実行用
            , IFNULL(t1.billing_state,t1.desiredprefecture__c) AS billing_state     -- 都道府県（現住所）もしくは お住まいの都道府県 を都道府県とする
            , t1.branch_text__c                                                     -- 担当拠点（テキスト）★★★【重要】Branch__cでは無いのでSalesForce担当者と連携する場合は要注意★★★
            , t1.branch_text__c AS department_in_charge__c                          -- 担当拠点（テキスト）を 担当部署とする
            , t2.name                                                               -- 氏名 -- 担当CA名
            , t1.owner_id                                                           -- 担当者 -- 担当CAのID
            , t1.status__c                                                          -- ステータス
            , t1.negotiation_status__c AS referral_status__c                        -- 交渉ステータス（最新）を 交渉ステータスとする
            , t1.deletion_hope_reason__c                                            -- 削除希望理由
            , t1.web_changehopetime__c AS web_changehopetime__c                     -- 希望登録時_希望時期
            , t1.utmsource__c AS utmsource__c_not_first                             -- utm_source ★★初回登録時の情報ではないため、便宜的に名称を変更している★★
            , t1.utmmedium__c AS utmmedium__c_not_first                             -- utm_medium ★★初回登録時の情報ではないため、便宜的に名称を変更している★★
            , t1.utmcampaign__c                                                     -- utm_campaign
            , t1.utmcontent__c                                                      -- utm_content
            , t1.utmterm__c                                                         -- utm_term
            , t1.reregisterutmsource__c                                             -- 再登録utm_source
            , t1.reregisterutmmedium__c                                             -- 再登録utm_medium
            , t1.reregisterutmcampaign__c                                           -- 再登録utm_campaign
            , t1.reregisterutmcontent__c                                            -- 再登録utm_content
            , t1.reregisterutmterm__c                                               -- 再登録utm_term
            , t1.gclid__c                                                           -- gclid
            , t1.inflow_route__c                                                    -- 流入経路URL
            , t1.registerinflowroute_url__c AS reregister_inflow_route__c           -- 再登録流入経路URL

            -- careerのみ --
            , DATE(NULL) AS saitourokubigaibukeiyu__c
            , CAST(NULL AS INT64) AS registration_route_fisrst_navi_kaigo__c
            , CAST(NULL AS INT64) AS registration_route_kyuzinzyanal__c
            , CAST(NULL AS INT64) AS registration_route_nursing__c
            , CAST(NULL AS INT64) AS registration_routekaigolila__c
            , CAST(NULL AS INT64) AS registration_route_care_job_navi__c
            , CAST(NULL AS INT64) AS registration_route_fisrst_navi__c
            , CAST(NULL AS INT64) AS registrationroutenurse_e__c
            , CAST(NULL AS INT64) AS registration_route_nurse__c
            , CAST(NULL AS INT64) AS registration_routenasusenka__c
            , CAST(NULL AS INT64) AS registration_route_childcare_job_navi__c
            , CAST(NULL AS STRING) AS registration_routelisujobs__c
            , CAST(NULL AS STRING) AS registration_route_medridgechildcares__c
            , CAST(NULL AS STRING) AS registration_route_nikkei_medicals__c
            , CAST(NULL AS STRING) AS nurseryteachermikata__c  
            , CAST(NULL AS INT64) AS registration_route_hoikunooshigoto__c
            , CAST(NULL AS INT64) AS registration_route_eiyoshinooshigoto__c
            , CAST(NULL AS INT64) AS registration_route_friend__c
            , CAST(NULL AS STRING) AS registration_route_trytworker__c
            , CAST(NULL AS STRING) AS registration_route_crm__c
            , CAST(NULL AS INT64) AS registration_routeyakukyari__c                 
            , CAST(NULL AS FLOAT64) AS age__c
            , CAST(NULL AS STRING) AS yuusensikakusyuukeiyou__c
            , CAST(NULL AS STRING) AS kiboukinmukeitaisyuukei__c
            , CAST(NULL AS STRING) AS employment_type_shift_pattern1__c
            , CAST(NULL AS STRING) AS affiliate_approval_key__c
            , t1.utmsource__c AS utmsource_first__c
            , t1.utmmedium__c AS utmmedium_first__c
            , CAST(NULL AS STRING) AS reregistre_web_requirements__c   
            , CAST(NULL AS STRING) AS reregistre_web_changehopetime__c  
            , CAST(NULL AS STRING) AS web_job_application_number__c 
            , DATE(NULL) AS job_change_time_from__c 
            , CAST(NULL AS STRING) AS registeredoccupation__pc                      
            , CAST(NULL AS STRING) AS import_type__c
            , CAST(NULL AS STRING) AS registration_route_owned_media__c
            , CAST(NULL AS STRING) AS registration_route_external_site__c           
            
            -- constのみ --
            , t1.registration_route01__c                                            -- 登録経路
            , t1.registration_route02__c                                            -- 登録経路（経路）
            , t1.desired_industry__c                                                -- 希望業種
            , t1.age_group__c                                                       -- 登録時年齢層
            , t1.desired_occupation__c                                              -- 希望職種（建設用）   
            , t1.experience_in_construction_management__c                           -- 施工管理のご経験
            , t1.field_supervisor_experience__c                                     -- 施工管理業界のご経験

            , CAST(NULL AS DATE) AS followupchangeddate__c                          
            , CAST(NULL AS STRING) AS person_contact_id                             
            , t1.last_modified_date                                                 -- 最終更新日 ※250711追加
            , CURRENT_DATE("Asia/Tokyo") AS run_date                                -- バッチ実行日
        FROM `tryt-bigquery-pj.marketing_edit_v2.01_00_const_account_job_seeker_temp_field` AS t1
        LEFT JOIN `tryt-bigquery-pj.production_tryt_informatica.const_user` AS t2
            ON t1.owner_id = t2.id  -- 求職者とユーザの紐づけ
        WHERE t1.registration_date__c >= target_start_date                         -- 登録日
            OR t1.saitourokubi_adkeiyu__c >= target_start_date                     -- 再登録日（重複）-- 再登録日（広告経由）と同義
            OR t1.saitourokubiseokeiyu__c >= target_start_date                     -- 再登録日（SEO経由）
            OR t1.saitourokubisyukeiyou__c >= target_start_date                    -- 再登録日（CRM経由）
    ),

    const_account_job_seeker_accumulated AS ( -- const_account_job_seekerからの引用
        SELECT
            -- career/const共通 --
            t1.id AS jsid                                                           -- 求職者ID
            , t1.cd__c                                                              -- SFID
            , DATE(t1.registration_date__c) AS registration_date__c                 -- 登録日
            , DATE(t1.saitourokubi_adkeiyu__c) AS saitourokubi_adkeiyu__c           -- 再登録日（重複）-- 再登録日（広告経由）と同義
            , DATE(t1.saitourokubiseokeiyu__c) AS saitourokubiseokeiyu__c           -- 再登録日（SEO経由）
            , DATE(t1.saitourokubisyukeiyou__c) AS saitourokubisyukeiyou__c         -- 再登録日（CRM経由）
            , DATE(t1.neg_stat_date03__c) AS dummy_step1_from_js                    -- コンタクト履歴において欠損している各ステップ毎の日付を補正する対応を後続のクエリで実行用
            , DATE(t1.neg_stat_date05__c) AS dummy_step2_from_js                    -- コンタクト履歴において欠損している各ステップ毎の日付を補正する対応を後続のクエリで実行用
            , DATE(t1.neg_stat_date08__c) AS dummy_step3_from_js                    -- コンタクト履歴において欠損している各ステップ毎の日付を補正する対応を後続のクエリで実行用
            , DATE(t1.neg_stat_date11__c) AS dummy_step4_from_js                    -- コンタクト履歴において欠損している各ステップ毎の日付を補正する対応を後続のクエリで実行用
            , DATE(t1.neg_stat_date14__c) AS dummy_step5_from_js                    -- コンタクト履歴において欠損している各ステップ毎の日付を補正する対応を後続のクエリで実行用
            , IFNULL(t1.billing_state,t1.desiredprefecture__c) AS billing_state     -- 都道府県（現住所）もしくは お住まいの都道府県 を都道府県とする
            , t1.branch_text__c                                                     -- 担当拠点（テキスト）★★★【重要】Branch__cでは無いのでSalesForce担当者と連携する場合は要注意★★★
            , t1.branch_text__c AS department_in_charge__c                          -- 担当拠点（テキスト）を 担当部署とする
            , t2.name                                                               -- 氏名 -- 担当CA名
            , t1.owner_id                                                           -- 担当者 -- 担当CAのID
            , t1.status__c                                                          -- ステータス
            , t1.negotiation_status__c AS referral_status__c                        -- 交渉ステータス（最新）を 交渉ステータスとする
            , t1.deletion_hope_reason__c                                            -- 削除希望理由
            , t1.web_changehopetime__c AS web_changehopetime__c                     -- 希望登録時_希望時期
            , t1.utmsource__c AS utmsource__c_not_first                             -- utm_source ★★初回登録時の情報ではないため、便宜的に名称を変更している★★
            , t1.utmmedium__c AS utmmedium__c_not_first                             -- utm_medium ★★初回登録時の情報ではないため、便宜的に名称を変更している★★
            , t1.utmcampaign__c                                                     -- utm_campaign
            , t1.utmcontent__c                                                      -- utm_content
            , t1.utmterm__c                                                         -- utm_term
            , t1.reregisterutmsource__c                                             -- 再登録utm_source
            , t1.reregisterutmmedium__c                                             -- 再登録utm_medium
            , t1.reregisterutmcampaign__c                                           -- 再登録utm_campaign
            , t1.reregisterutmcontent__c                                            -- 再登録utm_content
            , t1.reregisterutmterm__c                                               -- 再登録utm_term
            , t1.gclid__c                                                           -- gclid
            , t1.inflow_route__c                                                    -- 流入経路URL
            , t1.registerinflowroute_url__c AS reregister_inflow_route__c           -- 再登録流入経路URL

            -- careerのみ --
            , DATE(NULL) AS saitourokubigaibukeiyu__c
            , CAST(NULL AS INT64) AS registration_route_fisrst_navi_kaigo__c
            , CAST(NULL AS INT64) AS registration_route_kyuzinzyanal__c
            , CAST(NULL AS INT64) AS registration_route_nursing__c
            , CAST(NULL AS INT64) AS registration_routekaigolila__c
            , CAST(NULL AS INT64) AS registration_route_care_job_navi__c
            , CAST(NULL AS INT64) AS registration_route_fisrst_navi__c
            , CAST(NULL AS INT64) AS registrationroutenurse_e__c
            , CAST(NULL AS INT64) AS registration_route_nurse__c
            , CAST(NULL AS INT64) AS registration_routenasusenka__c
            , CAST(NULL AS INT64) AS registration_route_childcare_job_navi__c
            , CAST(NULL AS STRING) AS registration_routelisujobs__c
            , CAST(NULL AS STRING) AS registration_route_medridgechildcares__c
            , CAST(NULL AS STRING) AS registration_route_nikkei_medicals__c
            , CAST(NULL AS STRING) AS nurseryteachermikata__c  
            , CAST(NULL AS INT64) AS registration_route_hoikunooshigoto__c
            , CAST(NULL AS INT64) AS registration_route_eiyoshinooshigoto__c
            , CAST(NULL AS INT64) AS registration_route_friend__c
            , CAST(NULL AS STRING) AS registration_route_trytworker__c
            , CAST(NULL AS STRING) AS registration_route_crm__c
            , CAST(NULL AS INT64) AS registration_routeyakukyari__c                 
            , CAST(NULL AS FLOAT64) AS age__c
            , CAST(NULL AS STRING) AS yuusensikakusyuukeiyou__c
            , CAST(NULL AS STRING) AS kiboukinmukeitaisyuukei__c
            , CAST(NULL AS STRING) AS employment_type_shift_pattern1__c
            , CAST(NULL AS STRING) AS affiliate_approval_key__c
            , t1.utmsource__c AS utmsource_first__c
            , t1.utmmedium__c AS utmmedium_first__c
            , CAST(NULL AS STRING) AS reregistre_web_requirements__c   
            , CAST(NULL AS STRING) AS reregistre_web_changehopetime__c  
            , CAST(NULL AS STRING) AS web_job_application_number__c 
            , DATE(NULL) AS job_change_time_from__c 
            , CAST(NULL AS STRING) AS registeredoccupation__pc                      
            , CAST(NULL AS STRING) AS import_type__c
            , CAST(NULL AS STRING) AS registration_route_owned_media__c
            , CAST(NULL AS STRING) AS registration_route_external_site__c           
            
            -- constのみ --
            , t1.registration_route01__c                                            -- 登録経路
            , t1.registration_route02__c                                            -- 登録経路（経路）
            , t1.desired_industry__c                                                -- 希望業種
            , t1.age_group__c                                                       -- 登録時年齢層
            , t1.desired_occupation__c                                              -- 希望職種（建設用）
            , t1.experience_in_construction_management__c                           -- 施工管理のご経験
            , t1.field_supervisor_experience__c                                     -- 施工管理業界のご経験

            , CAST(NULL AS DATE) AS followupchangeddate__c                          
            , CAST(NULL AS STRING) AS person_contact_id                             
            , t1.last_modified_date                                                 -- 最終更新日 ※250711追加
            , t1.run_date                                                           -- バッチ実行日
        FROM `tryt-bigquery-pj.marketing_edit_v2.01_00_const_account_job_seeker_accumulated_temp_field` AS t1
        LEFT JOIN `tryt-bigquery-pj.production_tryt_informatica.const_user` AS t2
            ON t1.owner_id = t2.id  -- 求職者とユーザの紐づけ
        WHERE t1.registration_date__c >= target_start_date                         -- 登録日
            OR t1.saitourokubi_adkeiyu__c >= target_start_date                     -- 再登録日（重複）-- 再登録日（広告経由）と同義
            OR t1.saitourokubiseokeiyu__c >= target_start_date                     -- 再登録日（SEO経由）
            OR t1.saitourokubisyukeiyou__c >= target_start_date                    -- 再登録日（CRM経由）
    ),
    
    const_account_job_seeker_all AS ( -- job_seekerの積み上げテーブル（accumulated）と最新のjob_seekerをユニオン
        SELECT * FROM const_account_job_seeker
        UNION ALL
        SELECT * FROM const_account_job_seeker_accumulated
        ),

    account_integrated AS ( -- career/const_account_job_seekerのユニオン
        SELECT * FROM career_account_job_seeker_all
        UNION ALL
        SELECT * FROM const_account_job_seeker_all
        ),

    data_edit AS ( -- 〆日、日付項目の整形
        SELECT 
            *
            , run_date AS cutoff_date_pseudo -- 〆日（昨日〆）                                                        -- 後続のクエリで、登録日が未来になってしまっているレコードを除外するためだけに設定されている項目
            , IFNULL(registration_date__c, DATE('1000-01-01')) AS registration_date__c_for_calculation              -- 数式用に空白で便宜上1000年1月1日を返す
            , IFNULL(saitourokubi_adkeiyu__c, DATE('1000-01-01')) AS saitourokubi_adkeiyu__c_for_calculation        -- 数式用に空白で便宜上1000年1月1日を返す
            , IFNULL(saitourokubigaibukeiyu__c, DATE('1000-01-01')) AS saitourokubigaibukeiyu__c_for_calculation    -- 数式用に空白で便宜上1000年1月1日を返す
            , IFNULL(saitourokubiseokeiyu__c, DATE('1000-01-01')) AS saitourokubiseokeiyu__c_for_calculation        -- 数式用に空白で便宜上1000年1月1日を返す
            , IFNULL(saitourokubisyukeiyou__c, DATE('1000-01-01')) AS saitourokubisyukeiyou__c_for_calculation      -- 数式用に空白で便宜上1000年1月1日を返す
        FROM account_integrated
        )

--最終集計
SELECT 
    *
FROM data_edit;
-- marketing_edit_v2.01_01_career_const_account_job_seeker_accumulated



-- marketing_edit_v2.01_02_entrance_edit_accumulated
    -- 更新日：2026/04/14
    -- 作業者：細江
    -- 更新内容：判定No.(judge_no)論理矛盾の修正

/*
■実行内容
入口のKPIにおける流入経路判定と接触日（登録日）など、入口に関する基本情報を整形する
★★★「utm情報」が空白かつ「登録経路」が空白であればSEOと分類されるロジックになっている★★★
CRMのLINE施策など特定の経路においてutm情報の追加や、登録経路に関する項目変更が発生した場合、類似項目付近を確認し改修を行う

【注意】
ロジックについては2021年頃当時のMK内で、コンサル会社のリヴァンプ社による管理手法を踏襲しながら独自に構築されたものと思われ、このように記述された当時の理由/背景を把握できる社員は不在で、かつ完全性の検証/担保が困難である(241024 KI追記)
GA4とSFの接続に関する開発および検証が済み次第、経路判定をGA4からの情報を取得し運用予定であるが、その際に大幅に設計変更になるため各種整合性を確認すること
本テーブルは以降の経路判定の根幹となり、記述を誤ると当社のKPI運用(広告運用)に甚大な影響が発生するので留意すること

21年頃に作成されたロジックの説明(当時の資料)：https://trytgroup.sharepoint.com/:p:/s/marketing/Eeezv6FEI2xLm5-SI-v2ScMB465Isjr9pqB72inRoLkJVw?e=lrzhav 
経路判定用マスタシート：https://docs.google.com/spreadsheets/d/1tVy_iOad8mgyKCzG3XVbcKyyphGx0dosTHpRBb9DR80/edit?pli=1#gid=1457600782
(PK:cd__c)
*/

CREATE OR REPLACE TABLE `tryt-bigquery-pj.marketing_edit_v2.01_02_entrance_edit_accumulated` PARTITION BY contact_month1 CLUSTER BY occupation AS 
WITH 
    route_judge AS ( -- entry_route突合用に、KPIロジックに従い、求職者ごとに流入経路を判定　
        SELECT
            * EXCEPT(utmmedium_first__c)
            , CASE 
                WHEN DATE_ADD(registration_date__c_for_calculation, INTERVAL 3 MONTH) <= saitourokubi_adkeiyu__c_for_calculation -- 再登録日（広告経由）が、新規登録日 から 3カ月以上後
                    AND 
                        (
                            (
                                DATE_ADD(saitourokubigaibukeiyu__c_for_calculation, INTERVAL 3 MONTH) <= saitourokubi_adkeiyu__c_for_calculation -- 再登録日（広告経由）が、再登録日（外部媒体経由） から 3カ月以上後
                                AND DATE_ADD(saitourokubiseokeiyu__c_for_calculation, INTERVAL 3 MONTH) <= saitourokubi_adkeiyu__c_for_calculation -- 再登録日（広告経由）が、再登録日（SEO経由） から 3カ月以上後
                            )
                            OR 
                            (
                                (saitourokubigaibukeiyu__c_for_calculation BETWEEN saitourokubi_adkeiyu__c_for_calculation AND DATE_ADD(saitourokubi_adkeiyu__c_for_calculation, INTERVAL 3 MONTH) - 1) -- 再登録日（外部媒体経由）が、再登録日（広告経由） ～ 再登録日（広告経由）+3ヵ月
                                OR (saitourokubiseokeiyu__c_for_calculation BETWEEN saitourokubi_adkeiyu__c_for_calculation AND DATE_ADD(saitourokubi_adkeiyu__c_for_calculation, INTERVAL 3 MONTH) - 1) -- 再登録日（SEO経由）が、再登録日（広告経由） ～ 再登録日（広告経由）+3ヵ月            
                            ) 
                            OR 
                            (
                                (
                                    saitourokubi_adkeiyu__c_for_calculation BETWEEN saitourokubigaibukeiyu__c_for_calculation + 1 AND DATE_ADD(saitourokubigaibukeiyu__c_for_calculation, INTERVAL 3 MONTH) - 1 -- 再登録日（広告経由）が、再登録日（外部媒体経由）～ 再登録日（外部媒体経由）+3ヵ月
                                    AND saitourokubigaibukeiyu__c_for_calculation < DATE_ADD(registration_date__c_for_calculation, INTERVAL 3 MONTH) --再登録日（外部媒体経由）が、新規登録日から3ヵ月以内
                                )
                                OR 
                                (
                                    saitourokubi_adkeiyu__c_for_calculation BETWEEN saitourokubiseokeiyu__c_for_calculation + 1 AND DATE_ADD(saitourokubiseokeiyu__c_for_calculation, INTERVAL 3 MONTH) - 1 --再登録日（広告経由）が、再登録日（SEO経由）～ 再登録日（SEO経由）+3ヵ月
                                    AND saitourokubiseokeiyu__c_for_calculation < DATE_ADD(registration_date__c_for_calculation, INTERVAL 3 MONTH) -- 再登録日（SEO経由）が、新規登録日から3ヵ月以内
                                )
                            )
                        ) 
                    AND 
                        (
                            (utmsource__c_not_first IS NULL AND utmmedium__c_not_first IS NULL) -- utm情報が空白
                            AND (registration_route_fisrst_navi_kaigo__c IS NULL OR registration_route_fisrst_navi_kaigo__c = 0)
                            AND (registration_route_kyuzinzyanal__c IS NULL OR registration_route_kyuzinzyanal__c = 0)
                            AND (registration_route_nursing__c IS NULL OR registration_route_nursing__c = 0)
                            AND (registration_routekaigolila__c IS NULL OR registration_routekaigolila__c = 0)
                            AND (registration_route_care_job_navi__c IS NULL OR registration_route_care_job_navi__c = 0)
                            AND (registration_route_fisrst_navi__c IS NULL OR registration_route_fisrst_navi__c = 0)
                            AND (registrationroutenurse_e__c IS NULL OR registrationroutenurse_e__c = 0)
                            AND (registration_route_nurse__c IS NULL OR registration_route_nurse__c = 0)
                            AND (registration_routenasusenka__c IS NULL OR registration_routenasusenka__c = 0)
                            AND (registration_route_childcare_job_navi__c IS NULL OR registration_route_childcare_job_navi__c = 0)
                            AND (registration_routelisujobs__c IS NULL OR registration_routelisujobs__c = 'false')
                            AND (registration_route_medridgechildcares__c IS NULL OR registration_route_medridgechildcares__c = 'false')
                            AND (registration_route_nikkei_medicals__c IS NULL OR registration_route_nikkei_medicals__c = 'false')
                            AND (nurseryteachermikata__c IS NULL OR nurseryteachermikata__c = 'false')
                            AND (registration_route_owned_media__c IS NULL OR registration_route_owned_media__c = 'false') -- 外部媒体フラグが空白
                            AND (registration_route_external_site__c IS NULL OR registration_route_external_site__c = 'false') -- 外部媒体フラグが空白 ※20241111追加
                            AND (registration_routeyakukyari__c IS NULL OR registration_routeyakukyari__c = 0) ---- 20250115追加
                        ) -- utm情報が空白かつ登録経路が空白
                    THEN 1 -- judge_entry_routeが【SEO再登録】であると判定する
            
                WHEN DATE_ADD(registration_date__c_for_calculation, INTERVAL 3 MONTH) <= saitourokubi_adkeiyu__c_for_calculation -- 再登録日（広告経由）が、新規登録日 から 3カ月以上後
                    AND 
                        (
                            (
                                DATE_ADD(saitourokubigaibukeiyu__c_for_calculation, INTERVAL 3 MONTH) <= saitourokubi_adkeiyu__c_for_calculation -- 再登録日（広告経由）が、再登録日（外部媒体経由） から 3カ月以上後
                                AND DATE_ADD(saitourokubiseokeiyu__c_for_calculation, INTERVAL 3 MONTH) <= saitourokubi_adkeiyu__c_for_calculation -- 再登録日（広告経由）が、再登録日（SEO経由） から 3カ月以上後
                            ) 
                            OR 
                            (
                                (saitourokubigaibukeiyu__c_for_calculation BETWEEN saitourokubi_adkeiyu__c_for_calculation AND DATE_ADD(saitourokubi_adkeiyu__c_for_calculation, INTERVAL 3 MONTH) - 1) -- 再登録日（外部媒体経由）が、再登録日（広告経由） ～ 再登録日（広告経由）+3ヵ月
                                OR (saitourokubiseokeiyu__c_for_calculation BETWEEN saitourokubi_adkeiyu__c_for_calculation AND DATE_ADD(saitourokubi_adkeiyu__c_for_calculation, INTERVAL 3 MONTH) - 1) -- 再登録日（SEO経由）が、再登録日（広告経由） ～ 再登録日（広告経由）+3ヵ月
                            ) 
                            OR 
                            (
                                (
                                    saitourokubi_adkeiyu__c_for_calculation BETWEEN saitourokubigaibukeiyu__c_for_calculation + 1 AND DATE_ADD(saitourokubigaibukeiyu__c_for_calculation, INTERVAL 3 MONTH) - 1 -- 再登録日（広告経由）が、再登録日（外部媒体経由）～ 再登録日（外部媒体経由）+3ヵ月
                                    AND saitourokubigaibukeiyu__c_for_calculation < DATE_ADD(registration_date__c_for_calculation, INTERVAL 3 MONTH) -- 再登録日（外部媒体経由）が、新規登録日から3ヵ月以内
                                )
                                OR
                                (
                                    saitourokubi_adkeiyu__c_for_calculation BETWEEN saitourokubiseokeiyu__c_for_calculation + 1 AND DATE_ADD(saitourokubiseokeiyu__c_for_calculation, INTERVAL 3 MONTH) - 1 -- 再登録日（広告経由）が、再登録日（SEO経由）～ 再登録日（SEO経由）+3ヵ月
                                    AND saitourokubiseokeiyu__c_for_calculation < DATE_ADD(registration_date__c_for_calculation, INTERVAL 3 MONTH) -- 再登録日（SEO経由）が、新規登録日から3ヵ月以内
                                )
                            )
                        )
                    AND 
                        (
                            (utmsource__c_not_first IN('line' , 'LINE') AND utmmedium__c_not_first IN('CRM' , 'timeline' , 'rich_menu' , 'push'))
                            OR 
                            (utmsource__c_not_first = 'crm_lineat' AND (utmmedium__c_not_first = 'social' OR utmmedium__c_not_first IS NULL))
                            OR 
                            (utmsource__c_not_first = 'line' AND utmmedium__c_not_first IN('oa_richmenu/' , 'social'))
                            OR 
                            (utmsource__c_not_first IN('instagram' , 'twitter') AND utmmedium__c_not_first IN('CRM' , 'crm'))
                        ) -- utm情報がCRMLINE経由(twitterやInstagram施策を含む)の値である
                    THEN 2 -- judge_entry_routeが【CRM(LINE再登録)】であると判定する
                    
                WHEN DATE_ADD(registration_date__c_for_calculation, INTERVAL 3 MONTH) <= saitourokubi_adkeiyu__c_for_calculation -- 再登録日（広告経由）が、新規登録日 から 3カ月以上後
                    AND 
                        (
                            (
                                DATE_ADD(saitourokubigaibukeiyu__c_for_calculation, INTERVAL 3 MONTH) <= saitourokubi_adkeiyu__c_for_calculation -- 再登録日（広告経由）が、再登録日（外部媒体経由） から 3カ月以上後
                                AND DATE_ADD(saitourokubiseokeiyu__c_for_calculation, INTERVAL 3 MONTH) <= saitourokubi_adkeiyu__c_for_calculation -- 再登録日（広告経由）が、再登録日（SEO経由） から 3カ月以上後
                            ) 
                            OR 
                            (
                                (saitourokubigaibukeiyu__c_for_calculation BETWEEN saitourokubi_adkeiyu__c_for_calculation AND DATE_ADD(saitourokubi_adkeiyu__c_for_calculation, INTERVAL 3 MONTH) - 1) -- 再登録日（外部媒体経由）が、再登録日（広告経由） ～ 再登録日（広告経由）+3ヵ月
                                OR (saitourokubiseokeiyu__c_for_calculation BETWEEN saitourokubi_adkeiyu__c_for_calculation AND DATE_ADD(saitourokubi_adkeiyu__c_for_calculation, INTERVAL 3 MONTH) - 1) -- 再登録日（SEO経由）が、再登録日（広告経由） ～ 再登録日（広告経由）+3ヵ月
                            ) 
                            OR 
                            (
                                (
                                    saitourokubi_adkeiyu__c_for_calculation BETWEEN saitourokubigaibukeiyu__c_for_calculation + 1 AND DATE_ADD(saitourokubigaibukeiyu__c_for_calculation, INTERVAL 3 MONTH) - 1 -- 再登録日（広告経由）が、再登録日（外部媒体経由）～ 再登録日（外部媒体経由）+3ヵ月
                                    AND saitourokubigaibukeiyu__c_for_calculation < DATE_ADD(registration_date__c_for_calculation, INTERVAL 3 MONTH) -- 再登録日（外部媒体経由）が、新規登録日から3ヵ月以内
                                )
                                OR 
                                (
                                    saitourokubi_adkeiyu__c_for_calculation BETWEEN saitourokubiseokeiyu__c_for_calculation + 1 AND DATE_ADD(saitourokubiseokeiyu__c_for_calculation, INTERVAL 3 MONTH) - 1 -- 再登録日（広告経由）が、再登録日（SEO経由）～ 再登録日（SEO経由）+3ヵ月
                                    AND saitourokubiseokeiyu__c_for_calculation < DATE_ADD(registration_date__c_for_calculation, INTERVAL 3 MONTH) -- 再登録日（SEO経由）が、新規登録日から3ヵ月以内
                                )
                            )
                        )
                    AND utmmedium__c_not_first LIKE '%fullfunnel%' -- utm情報がフルファネル経由の値である
                    THEN 4 -- judge_entry_routeが【フルファネル再登録】であると判定する
                    
                WHEN DATE_ADD(registration_date__c_for_calculation, INTERVAL 3 MONTH) <= saitourokubi_adkeiyu__c_for_calculation -- 再登録日（広告経由）が、新規登録日 から 3カ月以上後
                    AND 
                        (
                            (
                                DATE_ADD(saitourokubigaibukeiyu__c_for_calculation, INTERVAL 3 MONTH) <= saitourokubi_adkeiyu__c_for_calculation -- 再登録日（広告経由）が、再登録日（外部媒体経由） から 3カ月以上後
                                AND DATE_ADD(saitourokubiseokeiyu__c_for_calculation, INTERVAL 3 MONTH) <= saitourokubi_adkeiyu__c_for_calculation -- 再登録日（広告経由）が、再登録日（SEO経由） から 3カ月以上後
                            )
                            OR 
                            (
                                (saitourokubigaibukeiyu__c_for_calculation BETWEEN saitourokubi_adkeiyu__c_for_calculation AND DATE_ADD(saitourokubi_adkeiyu__c_for_calculation, INTERVAL 3 MONTH) - 1) -- 再登録日（外部媒体経由）が、再登録日（広告経由） ～ 再登録日（広告経由）+3ヵ月
                                OR (saitourokubiseokeiyu__c_for_calculation BETWEEN saitourokubi_adkeiyu__c_for_calculation AND DATE_ADD(saitourokubi_adkeiyu__c_for_calculation, INTERVAL 3 MONTH) - 1) -- 再登録日（SEO経由）が、再登録日（広告経由） ～ 再登録日（広告経由）+3ヵ月
                            ) 
                            OR 
                            (
                                (
                                    saitourokubi_adkeiyu__c_for_calculation BETWEEN saitourokubigaibukeiyu__c_for_calculation + 1 AND DATE_ADD(saitourokubigaibukeiyu__c_for_calculation, INTERVAL 3 MONTH) - 1 -- 再登録日（広告経由）が、再登録日（外部媒体経由）～ 再登録日（外部媒体経由）+3ヵ月
                                    AND saitourokubigaibukeiyu__c_for_calculation < DATE_ADD(registration_date__c_for_calculation, INTERVAL 3 MONTH) -- 再登録日（外部媒体経由）が、新規登録日から3ヵ月以内
                                )
                                OR 
                                (
                                    saitourokubi_adkeiyu__c_for_calculation BETWEEN saitourokubiseokeiyu__c_for_calculation + 1 AND DATE_ADD(saitourokubiseokeiyu__c_for_calculation, INTERVAL 3 MONTH) - 1 -- 再登録日（広告経由）が、再登録日（SEO経由）～ 再登録日（SEO経由）+3ヵ月
                                    AND saitourokubiseokeiyu__c_for_calculation < DATE_ADD(registration_date__c_for_calculation, INTERVAL 3 MONTH) -- 再登録日（SEO経由）が、新規登録日から3ヵ月以内
                                )
                            )
                        ) 
                    AND 
                        (
                            (
                                CASE WHEN 
                                        (
                                            utmsource__c_not_first IS NULL 
                                            AND utmmedium__c_not_first IS NULL 
                                            AND (registration_route_fisrst_navi_kaigo__c IS NULL OR registration_route_fisrst_navi_kaigo__c = 0) 
                                            AND (registration_route_kyuzinzyanal__c IS NULL OR registration_route_kyuzinzyanal__c = 0) 
                                            AND (registration_route_nursing__c IS NULL OR registration_route_nursing__c = 0) 
                                            AND (registration_routekaigolila__c IS NULL OR registration_routekaigolila__c = 0) 
                                            AND (registration_route_care_job_navi__c IS NULL OR registration_route_care_job_navi__c = 0) 
                                            AND (registration_route_fisrst_navi__c IS NULL OR registration_route_fisrst_navi__c = 0) 
                                            AND (registrationroutenurse_e__c IS NULL OR registrationroutenurse_e__c = 0) 
                                            AND (registration_route_nurse__c IS NULL OR registration_route_nurse__c = 0) 
                                            AND (registration_routenasusenka__c IS NULL OR registration_routenasusenka__c = 0) 
                                            AND (registration_route_childcare_job_navi__c IS NULL OR registration_route_childcare_job_navi__c = 0) 
                                            AND (registration_routelisujobs__c IS NULL OR registration_routelisujobs__c = 'false') 
                                            AND (registration_route_medridgechildcares__c IS NULL OR registration_route_medridgechildcares__c = 'false') 
                                            AND (registration_route_nikkei_medicals__c IS NULL OR registration_route_nikkei_medicals__c = 'false') 
                                            AND (nurseryteachermikata__c IS NULL OR nurseryteachermikata__c = 'false')
                                            AND (registration_route_owned_media__c IS NULL OR registration_route_owned_media__c = 'false')
                                            AND (registration_route_external_site__c IS NULL OR registration_route_external_site__c = 'false') -- ※20241111追加
                                            AND (registration_routeyakukyari__c IS NULL OR registration_routeyakukyari__c = 0) ---- 20250115追加
                                        ) = TRUE THEN 1 ELSE 0 END
                                + 
                                CASE WHEN 
                                        (
                                            (utmsource__c_not_first IN('line' , 'LINE') AND utmmedium__c_not_first IN('CRM' , 'timeline' , 'rich_menu' , 'push'))
                                            OR 
                                            (utmsource__c_not_first = 'crm_lineat' AND (utmmedium__c_not_first = 'social' OR utmmedium__c_not_first IS NULL))
                                            OR 
                                            (utmsource__c_not_first = 'line' AND utmmedium__c_not_first IN('oa_richmenu/' , 'social'))
                                            OR 
                                            (utmsource__c_not_first IN('instagram' , 'twitter') AND utmmedium__c_not_first IN('CRM' , 'crm'))
                                        ) = TRUE THEN 1 ELSE 0 END
                                + 
                                CASE WHEN utmmedium__c_not_first LIKE '%fullfunnel%' THEN 1 ELSE 0 END
                            )= 0
                        ) -- 再登録 かつ 登録情報が空白でない(SEO経由ではない) かつ utm情報がCRM経由でない かつ utm情報がフルファネル経由でない 場合
                    THEN 5 -- judge_entry_routeが【広告再登録】であると判定する
            
                WHEN DATE_ADD(registration_date__c_for_calculation, INTERVAL 3 MONTH) <= saitourokubigaibukeiyu__c_for_calculation --【注意】再登録日（外部媒体経由）が、新規登録日 から 3カ月以上後 ※他と異なる
                    AND 
                        (
                            (
                                DATE_ADD(saitourokubi_adkeiyu__c_for_calculation, INTERVAL 3 MONTH) <= saitourokubigaibukeiyu__c_for_calculation --【注意】再登録日（外部媒体経由）が、再登録日（広告経由） から 3カ月以上後 ※他と異なる
                                AND DATE_ADD(saitourokubiseokeiyu__c_for_calculation, INTERVAL 3 MONTH) <= saitourokubigaibukeiyu__c_for_calculation --【注意】再登録日（外部媒体経由）が、再登録日（SEO経由） から 3カ月以上後 ※他と異なる
                            ) 
                            OR 
                            (
                                (saitourokubi_adkeiyu__c_for_calculation BETWEEN saitourokubigaibukeiyu__c_for_calculation AND DATE_ADD(saitourokubigaibukeiyu__c_for_calculation, INTERVAL 3 MONTH) - 1) --【注意】再登録日（広告経由）が、再登録日（外部媒体経由） ～ 再登録日（外部媒体経由）+3ヵ月 ※他と異なる
                                OR (saitourokubiseokeiyu__c_for_calculation BETWEEN saitourokubigaibukeiyu__c_for_calculation AND DATE_ADD(saitourokubigaibukeiyu__c_for_calculation, INTERVAL 3 MONTH) - 1) --【注意】再登録日（SEO経由）が、再登録日（外部媒体経由） ～ 再登録日（外部媒体経由）+3ヵ月 ※他と異なる
                            ) 
                            OR 
                            (
                                (
                                    saitourokubigaibukeiyu__c_for_calculation BETWEEN saitourokubi_adkeiyu__c_for_calculation + 1 AND DATE_ADD(saitourokubi_adkeiyu__c_for_calculation, INTERVAL 3 MONTH) - 1 -- 【注意】再登録日（外部媒体経由）が、再登録日（広告経由）～ 再登録日（広告経由）+3ヵ月 ※他と異なる
                                    AND saitourokubi_adkeiyu__c_for_calculation < DATE_ADD(registration_date__c_for_calculation, INTERVAL 3 MONTH) -- 【注意】再登録日（広告経由）が、新規登録日から3ヵ月以内 ※他と異なる
                                )
                                OR 
                                (
                                    saitourokubigaibukeiyu__c_for_calculation BETWEEN saitourokubiseokeiyu__c_for_calculation + 1 AND DATE_ADD(saitourokubiseokeiyu__c_for_calculation, INTERVAL 3 MONTH) - 1 --【注意】再登録日（外部媒体経由）が、再登録日（SEO経由）～ 再登録日（SEO経由）+3ヵ月 ※他と異なる
                                    AND saitourokubiseokeiyu__c_for_calculation < DATE_ADD(registration_date__c_for_calculation, INTERVAL 3 MONTH) -- 再登録日（SEO経由）が、新規登録日から3ヵ月以内
                                ) 
                            ) 
                        ) 
                    THEN 6 -- judge_entry_routeが【広告再登録】であると判定する
                
                WHEN DATE_ADD(registration_date__c_for_calculation, INTERVAL 3 MONTH)  <= saitourokubiseokeiyu__c_for_calculation --【注意】再登録日（SEO経由）が、新規登録日 から 3カ月以上後 ※他と異なる
                    AND 
                        (
                            (
                                DATE_ADD(saitourokubi_adkeiyu__c_for_calculation, INTERVAL 3 MONTH) <= saitourokubiseokeiyu__c_for_calculation -- 【注意】再登録日（SEO経由）が、再登録日（広告経由） から 3カ月以上後 ※他と異なる
                                AND DATE_ADD(saitourokubigaibukeiyu__c_for_calculation, INTERVAL 3 MONTH) <= saitourokubiseokeiyu__c_for_calculation -- 【注意】再登録日（SEO経由）が、再登録日（外部媒体経由） から 3カ月以上後 ※他と異なる
                            )
                            OR 
                            (
                                (saitourokubi_adkeiyu__c_for_calculation BETWEEN saitourokubiseokeiyu__c_for_calculation AND DATE_ADD(saitourokubiseokeiyu__c_for_calculation, INTERVAL 3 MONTH) - 1) --【注意】再登録日（広告経由）が、再登録日（SEO経由） ～ 再登録日（SEO経由）+3ヵ月 ※他と異なる
                                OR (saitourokubigaibukeiyu__c_for_calculation BETWEEN saitourokubiseokeiyu__c_for_calculation AND DATE_ADD(saitourokubiseokeiyu__c_for_calculation, INTERVAL 3 MONTH) - 1) --【注意】再登録日（外部媒体経由）が、再登録日（SEO経由） ～ 再登録日（SEO経由）+3ヵ月 ※他と異なる
                            ) 
                            OR 
                            (
                                (
                                    saitourokubiseokeiyu__c_for_calculation BETWEEN saitourokubi_adkeiyu__c_for_calculation + 1 AND DATE_ADD(saitourokubi_adkeiyu__c_for_calculation, INTERVAL 3 MONTH) - 1 --【注意】再登録日（SEO経由）が、再登録日（広告経由）～ 再登録日（広告経由）+3ヵ月※他と異なる
                                    AND saitourokubi_adkeiyu__c_for_calculation < DATE_ADD(registration_date__c_for_calculation, INTERVAL 3 MONTH) -- 【注意】再登録日（広告経由）が、新規登録日から3ヵ月以内 ※他と異なる
                                )
                                OR 
                                (
                                    saitourokubiseokeiyu__c_for_calculation BETWEEN saitourokubigaibukeiyu__c_for_calculation + 1 AND DATE_ADD(saitourokubigaibukeiyu__c_for_calculation, INTERVAL 3 MONTH) - 1 -- 【注意】再登録日（SEO経由）が、再登録日（外部媒体経由）～ 再登録日（外部媒体経由）+3ヵ月 ※他と異なる
                                    AND saitourokubigaibukeiyu__c_for_calculation < DATE_ADD(registration_date__c_for_calculation, INTERVAL 3 MONTH) -- 【注意】再登録日（外部媒体経由）が、新規登録日から3ヵ月以内 ※他と異なる
                                )
                            ) 
                        ) 
                    THEN 7 -- judge_entry_routeが【SEO再登録】であると判定する
            
                WHEN 
                    (
                        (utmsource_first__c IS NULL AND utmmedium_first__c IS NULL)
                        AND (registration_route_fisrst_navi_kaigo__c IS NULL OR registration_route_fisrst_navi_kaigo__c = 0)
                        AND (registration_route_kyuzinzyanal__c IS NULL OR registration_route_kyuzinzyanal__c = 0)
                        AND (registration_route_nursing__c IS NULL OR registration_route_nursing__c = 0)
                        AND (registration_routekaigolila__c IS NULL OR registration_routekaigolila__c = 0)
                        AND (registration_route_care_job_navi__c IS NULL OR registration_route_care_job_navi__c = 0)
                        AND (registration_route_fisrst_navi__c IS NULL OR registration_route_fisrst_navi__c = 0)
                        AND (registrationroutenurse_e__c IS NULL OR registrationroutenurse_e__c = 0)
                        AND (registration_route_nurse__c IS NULL OR registration_route_nurse__c = 0)
                        AND (registration_routenasusenka__c IS NULL OR registration_routenasusenka__c = 0)
                        AND (registration_route_childcare_job_navi__c IS NULL OR registration_route_childcare_job_navi__c = 0)
                        AND (registration_routelisujobs__c IS NULL OR registration_routelisujobs__c = 'false')
                        AND (registration_route_medridgechildcares__c IS NULL OR registration_route_medridgechildcares__c = 'false')
                        AND (registration_route_nikkei_medicals__c IS NULL OR registration_route_nikkei_medicals__c = 'false')
                        AND (nurseryteachermikata__c IS NULL OR nurseryteachermikata__c = 'false')
                        AND (registration_route_owned_media__c IS NULL OR registration_route_owned_media__c = 'false')
                        AND (registration_route_external_site__c IS NULL OR registration_route_external_site__c = 'false') --※20241111追加
                        AND (registration_route_friend__c IS NULL OR registration_route_friend__c = 0)
                        AND (registration_routeyakukyari__c IS NULL OR registration_routeyakukyari__c = 0) ---- 20250115追加
                    ) -- utm情報が空白かつ登録経路が空白
                    THEN 101 -- judge_entry_routeが【SEO新規登録】であると判定する 
                      
                WHEN
                    (
                        (utmsource_first__c IN('line' , 'LINE') AND utmmedium_first__c IN('CRM' , 'timeline' , 'rich_menu' , 'push'))
                        OR 
                        (utmsource_first__c = 'crm_lineat' AND (utmmedium_first__c = 'social' OR utmmedium_first__c IS NULL))
                        OR 
                        (utmsource_first__c = 'line' AND utmmedium_first__c IN('oa_richmenu/' , 'social'))
                        OR 
                        (utmsource_first__c IN('instagram' , 'twitter') AND utmmedium_first__c IN('CRM')) 
                    ) -- utm情報がCRMLINE経由(twitterやInstagramを含む)である
                    THEN 102 -- judge_entry_routeが【CRM(LINE) 新規登録】であると判定する
                    
                WHEN 
                    (
                        (
                            utmsource_first__c IN('mailmagazine' , 'sms' , 'line' , 'chirashi') 
                            AND 
                            (
                                utmmedium_first__c IN('CRM' , 'CS' , 'NU' , 'crm' , 'cs' , 'nu') 
                                OR utmmedium_first__c LIKE 'cs_%' 
                                OR utmmedium_first__c LIKE 'is_%'
                            )
                        )
                        OR (utmsource_first__c = 'sf' AND utmmedium_first__c = 'sales') 
                        OR (registration_route_friend__c IS NULL OR registration_route_friend__c = 0) = FALSE 
                    ) -- utm情報が友人紹介経由 である
                    THEN 103 -- judge_entry_routeが【CRM(友人紹介)】であると判定する
                
                WHEN utmmedium_first__c LIKE '%fullfunnel%'
                    THEN 104 -- judge_entry_routeが【フルファネル新規登録】であると判定する
                
                WHEN 
                    (
                        (
                            CASE WHEN 
                                    (
                                        utmsource_first__c IS NULL 
                                        AND utmmedium_first__c IS NULL 
                                        AND (registration_route_fisrst_navi_kaigo__c IS NULL OR registration_route_fisrst_navi_kaigo__c = 0) 
                                        AND (registration_route_kyuzinzyanal__c IS NULL OR registration_route_kyuzinzyanal__c = 0) 
                                        AND (registration_route_nursing__c IS NULL OR registration_route_nursing__c = 0) 
                                        AND (registration_routekaigolila__c IS NULL OR registration_routekaigolila__c = 0) 
                                        AND (registration_route_care_job_navi__c IS NULL OR registration_route_care_job_navi__c = 0) 
                                        AND (registration_route_fisrst_navi__c IS NULL OR registration_route_fisrst_navi__c = 0) 
                                        AND (registrationroutenurse_e__c IS NULL OR registrationroutenurse_e__c = 0) 
                                        AND (registration_route_nurse__c IS NULL OR registration_route_nurse__c = 0) 
                                        AND (registration_routenasusenka__c IS NULL OR registration_routenasusenka__c = 0) 
                                        AND (registration_route_childcare_job_navi__c IS NULL OR registration_route_childcare_job_navi__c = 0) 
                                        AND (registration_routelisujobs__c IS NULL OR registration_routelisujobs__c = 'false') 
                                        AND (registration_route_medridgechildcares__c IS NULL OR registration_route_medridgechildcares__c = 'false') 
                                        AND (registration_route_nikkei_medicals__c IS NULL OR registration_route_nikkei_medicals__c = 'false') 
                                        AND (nurseryteachermikata__c IS NULL OR nurseryteachermikata__c = 'false') 
                                        AND (registration_route_owned_media__c IS NULL OR registration_route_owned_media__c = 'false')
                                        AND (registration_route_external_site__c IS NULL OR registration_route_external_site__c = 'false')  -- ※20241111追加
                                        AND (registration_routeyakukyari__c IS NULL OR registration_routeyakukyari__c = 0) ---- 20250115追加
                                    ) = TRUE THEN 1 ELSE 0 END
                            + 
                            CASE WHEN 
                                    (
                                        (utmsource_first__c IN('line' , 'LINE') AND utmmedium_first__c IN('CRM' , 'timeline' , 'rich_menu' , 'push'))
                                        OR 
                                        (utmsource_first__c = 'crm_lineat' AND (utmmedium_first__c = 'social' OR utmmedium_first__c IS NULL))
                                        OR 
                                        (utmsource_first__c = 'line' AND utmmedium_first__c IN('oa_richmenu/' , 'social'))
                                        OR 
                                        (utmsource_first__c IN('instagram' , 'twitter') AND utmmedium_first__c IN('CRM')
                                        )
                                    ) = TRUE THEN 1 ELSE 0 END
                            + 
                            CASE WHEN 
                                    (
                                        (
                                            utmsource_first__c IN('mailmagazine' , 'sms' , 'line' , 'chirashi') 
                                            AND 
                                            (
                                                utmmedium_first__c IN('CRM' , 'CS' , 'NU' , 'crm' , 'cs' , 'nu') 
                                                OR utmmedium_first__c LIKE 'cs_%' 
                                                OR utmmedium_first__c LIKE 'is_%'
                                            )
                                        )
                                        OR 
                                        (utmsource_first__c = 'sf' AND utmmedium_first__c = 'sales')  
                                        OR 
                                        (registration_route_friend__c IS NULL OR registration_route_friend__c = 0) = FALSE
                                    ) = TRUE THEN 1 ELSE 0 END
                            + 
                            CASE WHEN utmmedium_first__c LIKE '%fullfunnel%' THEN 1 ELSE 0 END
                        ) = 0
                    ) -- utm情報が空白でない(SEO経由ではない) かつ登録情報が空白でない(SEO経由ではない) かつ utm情報がCRM/友人紹介経由でない かつ utm情報がフルファネル経由でない
                    THEN 105 -- judge_entry_routeが【広告新規登録】であると判定する
                    
                ELSE 0 
            END AS judge_no -- 判定No.
        FROM `tryt-bigquery-pj.marketing_edit_v2.01_01_career_const_account_job_seeker_accumulated`
        ),

    entry_route_contact_date AS ( -- KPIロジックに基づき付与された判定Noを基に、entry_routeを突合し、「contact_date(接触日)」を作成する
        SELECT
            t1.* EXCEPT(judge_no)
            , t2.entry_route                                                        -- 分類
            , t2.judge_entry_route                                                  -- 判定
            , t2.new_entry_flag                                                     -- 新規フラグ
            , CASE 
                WHEN t2.contact_no = 1 THEN t1.registration_date__c                 -- 登録日
                WHEN t2.contact_no = 2 THEN t1.saitourokubi_adkeiyu__c              -- 再登録日（広告経由）
                WHEN t2.contact_no = 3 THEN t1.saitourokubigaibukeiyu__c            -- 再登録日（外部経由）
                WHEN t2.contact_no = 4 THEN t1.saitourokubiseokeiyu__c              -- 再登録日（SEO経由）
                ELSE NULL 
            END AS contact_date                                                     -- 接触日            
        FROM route_judge AS t1
        LEFT JOIN `tryt-bigquery-pj.production_tryt.master_judge_no_v2` AS t2       -- 流入経路判定用マスタ https://docs.google.com/spreadsheets/d/1tVy_iOad8mgyKCzG3XVbcKyyphGx0dosTHpRBb9DR80/edit?gid=1457600782#gid=1457600782
            ON t1.judge_no = t2.jugdge_no  -- 流入経路の突合
        ),

    contact_month_occupation_area AS ( -- 「担当拠点」を基に「職種」・「支社」を突合、「contact_date」の項目を基にcontact_monthの項目を作成
        SELECT
            t1.* EXCEPT(cutoff_date_pseudo)                                         -- 〆日（昨日〆）
            , CASE 
                WHEN t1.cutoff_date_pseudo < t1.contact_date THEN NULL 
                ELSE DATE_TRUNC(t1.contact_date , MONTH) 
            END AS contact_month1                                                   -- 接触月1
            , t2.branch                                                             -- 担当拠点
            , CASE
                WHEN t2.occupation IS NOT NULL THEN t2.occupation
                WHEN t2.occupation IS NULL AND t1.status__c = '配布対象外' AND t1.registeredoccupation__pc  = '保育士' THEN '保育士'
            END AS occupation                                                       -- 職種
            , CASE
                WHEN t2.area IS NOT NULL THEN t2.area
                WHEN t2.area IS NULL AND t1.status__c = '配布対象外' AND t1.registeredoccupation__pc  = '保育士' THEN '配布対象外'
            END AS area                                                             -- 支社
            , CASE 
                WHEN (t1.status__c = '削除希望' OR t1.status__c = '☆') OR (t2.occupation = '施工管理' AND t1.status__c = '削除希望依頼') THEN 0
                ELSE 1 
            END AS entrance_flag                                                    -- ★★★★★★★★★★入口フラグ(接触数カウントから削除希望や☆の求職者を除外するために活用)★★★★★★★★★★
        FROM entry_route_contact_date AS t1
        LEFT JOIN `tryt-bigquery-pj.production_tryt.master_branch` AS t2            -- 拠点マスタ https://docs.google.com/spreadsheets/d/1tVy_iOad8mgyKCzG3XVbcKyyphGx0dosTHpRBb9DR80/edit?gid=1094227535#gid=1094227535
            ON t1.branch_text__c = t2.branch                                        -- 職種・支社の紐づけ
        WHERE t1.contact_date <= t1.cutoff_date_pseudo
            AND
                (
                    t2.occupation NOT IN('カレッジ')
                    OR
                    (t1.status__c = '配布対象外' AND t1.registeredoccupation__pc  = '保育士')     -- 20241111追加 (保育にて配布が行われない登録者も集計するため)
                )
            /* 
            ★★★★★★★★★★重要★★★★★★★★★★
            以下のクエリで全て、上記のWHERE句の条件に従って集計される=マスタに存在しない拠点に紐づくレコードは一切集計されない、ただし保育は配布されない求職者も集計される
            →25年1月時点では、SFの求職者オブジェクトで職種を明示的に保持している項目が存在しない
            →【当日の求職者オブジェクト】における、求職者に紐づく担当CA名によって決まる担当拠点(ex.「東京（介護）」)のカッコの中の値を抽出することで職種を判定する運用としている
            【注意】担当拠点の値(career_account_job_seeker.branch_text__c)の割り振りは、前日分における登録者に関して毎朝9時頃に所長がSF上で手動で行う建付けとなっており、そのSFの値が11時にBQに連携されるが、インシデントにより各種集計値に異常が発生する場合があるので、career_account_job_seekerのバックアップテーブル等を調査し、SF課/開発課等に連絡すること
            */                     
        ),

    entrance AS ( -- 入口の項目を整形
        SELECT
            * EXCEPT(last_modified_date)
            , CASE 
                WHEN experience_in_construction_management__c = 1 AND entrance_flag = 1 THEN 1 
                ELSE 0 
            END AS experience                                                       -- 施工管理経験者
            , CASE 
                WHEN experience_in_construction_management__c = 1 AND entrance_flag = 1 AND (age_group__c = '0歳～17歳' OR age_group__c = '18歳～24歳' OR age_group__c = '25歳～29歳') THEN 1 
                ELSE 0 
            END AS young_experience                                                 -- 若年層経験者
            , CASE 
                WHEN experience_in_construction_management__c = 1 THEN '経験者' 
                WHEN experience_in_construction_management__c = 0 THEN '未経験者' 
                ELSE '不明' 
            END AS construction_management_experience                               -- 施工管理経験有無
            , CASE 
                WHEN field_supervisor_experience__c = 1 THEN '経験者' 
                WHEN field_supervisor_experience__c = 0 THEN '未経験者'
                ELSE '不明' 
            END AS construction_industry_experience                                 -- 施工管理業界経験有無
            , CASE 
                WHEN age__c IS NULL THEN 
                    CASE 
                        WHEN age_group__c = '0歳～17歳' OR age_group__c = '18歳～24歳' OR age_group__c = '25歳～29歳' THEN '若年層' 
                        WHEN age_group__c = '30歳～39歳' OR age_group__c = '40歳～49歳' THEN 'ミドル' 
                        WHEN age_group__c = '50歳～59歳' OR age_group__c = '60歳～' THEN 'シニア' 
                        ELSE NULL 
                    END
                WHEN age__c BETWEEN 10 AND 20 - 1 THEN '10代' 
                WHEN age__c BETWEEN 20 AND 30 - 1 THEN '20代' 
                WHEN age__c BETWEEN 30 AND 40 - 1 THEN '30代' 
                WHEN age__c BETWEEN 40 AND 50 - 1 THEN '40代' 
                WHEN age__c BETWEEN 50 AND 60 - 1 THEN '50代' 
                WHEN age__c BETWEEN 60 AND 70 - 1 THEN '60代' 
                WHEN age__c BETWEEN 70 AND 80 - 1 THEN '70代' 
                WHEN age__c BETWEEN 80 AND 90 - 1 THEN '80代'
                ELSE NULL 
            END AS age_group                                                        -- 年齢層    
            , IFNULL(kiboukinmukeitaisyuukei__c,employment_type_shift_pattern1__c) AS work_style  -- 希望勤務形態
            , CASE 
                WHEN REGEXP_CONTAINS(web_changehopetime__c, '^20(2[6-9]|[3-9][0-9])年4月$') = TRUE THEN web_changehopetime__c   -- "20XX年4月"の値が存在する場合
                ELSE
                    CASE
                        WHEN job_change_time_from__c IS NULL OR contact_date > job_change_time_from__c THEN 
                            CASE 
                                WHEN REPLACE(UPPER(NORMALIZE(web_changehopetime__c,NFKC)),' ','') IS NULL THEN 'その他'
                                WHEN REGEXP_CONTAINS(REPLACE(UPPER(NORMALIZE(web_changehopetime__c,NFKC)),' ',''), '(1ヶ月以内|1ヵ月以内|1ケ月以内|1か月以内|決まり次第)') THEN '1か月以内'
                                WHEN REGEXP_CONTAINS(REPLACE(UPPER(NORMALIZE(web_changehopetime__c,NFKC)),' ',''), '(3ヶ月以内|3ヵ月以内|3ケ月以内|3か月以内)') THEN '3か月以内'
                                WHEN REGEXP_CONTAINS(REPLACE(UPPER(NORMALIZE(web_changehopetime__c,NFKC)),' ',''), '(6ヶ月以内|6ヵ月以内|6ケ月以内|6か月以内|半年以内)') THEN '6か月以内'
                                WHEN REGEXP_CONTAINS(REPLACE(UPPER(NORMALIZE(web_changehopetime__c,NFKC)),' ',''), '(9ヶ月以内|9ヵ月以内|9ケ月以内|9か月以内)') THEN '9か月以内'
                                WHEN REGEXP_CONTAINS(REPLACE(UPPER(NORMALIZE(web_changehopetime__c,NFKC)),' ',''), '(12ヶ月以内|12ヵ月以内|12ケ月以内|12か月以内|1年以内)') THEN '1年以内'
                                WHEN REPLACE(UPPER(NORMALIZE(web_changehopetime__c,NFKC)),' ','') LIKE '%1年以上%' THEN '1年以上先'
                                WHEN REGEXP_CONTAINS(REPLACE(UPPER(NORMALIZE(web_changehopetime__c,NFKC)),' ',''), '(いつでも|すぐにでも|良いところがあれば|よいところがあれば|即日勤務可能)') THEN 'いつでも'
                                WHEN REPLACE(UPPER(NORMALIZE(web_changehopetime__c,NFKC)),' ','') LIKE '%未定%' THEN '未定' 
                                ELSE 'その他' 
                            END
                        WHEN DATE_ADD(contact_date , INTERVAL 1 MONTH) > job_change_time_from__c THEN '1か月以内'
                        WHEN DATE_ADD(contact_date , INTERVAL 3 MONTH) > job_change_time_from__c THEN '3か月以内'
                        WHEN DATE_ADD(contact_date , INTERVAL 6 MONTH) > job_change_time_from__c THEN '6か月以内'
                        WHEN DATE_ADD(contact_date , INTERVAL 9 MONTH) > job_change_time_from__c THEN '9か月以内'
                        WHEN DATE_ADD(contact_date , INTERVAL 12 MONTH) > job_change_time_from__c THEN '1年以内'
                        ELSE '1年以上先' 
                    END
            END AS timing                                                           -- 希望転職時期 【重要】複数の項目が引用されている(※整合性は不明なので要注意※)
            , CASE WHEN desired_occupation__c IS NULL THEN 0 WHEN desired_occupation__c LIKE '%建築施工管理%' THEN 1 ELSE 0 END AS const_desired_1      -- 建築施工管理
            , CASE WHEN desired_occupation__c IS NULL THEN 0 WHEN desired_occupation__c LIKE '%土木施工管理%' THEN 1 ELSE 0 END AS const_desired_2      -- 土木施工管理
            , CASE WHEN desired_occupation__c IS NULL THEN 0 WHEN desired_occupation__c LIKE '%電気施工管理%' THEN 1 ELSE 0 END AS const_desired_3      -- 電気施工管理
            , CASE WHEN desired_occupation__c IS NULL THEN 0 WHEN desired_occupation__c LIKE '%電気設備管理%' THEN 1 ELSE 0 END AS const_desired_4      -- 電気設備管理
            , CASE WHEN desired_occupation__c IS NULL THEN 0 WHEN desired_occupation__c LIKE '%施工図・設計%' THEN 1 ELSE 0 END AS const_desired_5      -- 施工図・設計
            , CASE WHEN desired_occupation__c IS NULL THEN 0 WHEN desired_occupation__c LIKE '%施工図作成%' THEN 1 ELSE 0 END AS const_desired_6        -- 施工図作成
            , CASE WHEN desired_occupation__c IS NULL THEN 0 WHEN desired_occupation__c LIKE '%空調設備施工管理%' THEN 1 ELSE 0 END AS const_desired_7   -- 空調設備施工管理
            , CASE WHEN desired_occupation__c IS NULL THEN 0 WHEN desired_occupation__c LIKE '%CADオペレーター%' THEN 1 ELSE 0 END AS const_desired_8   -- CADオペレーター
            , CASE WHEN desired_occupation__c IS NULL THEN 0 WHEN desired_occupation__c LIKE '%設備施工管理%' THEN 1 ELSE 0 END AS const_desired_9      -- 設備施工管理
            , CASE WHEN desired_occupation__c IS NULL THEN 0 WHEN desired_occupation__c LIKE '%衛生設備施工管理%' THEN 1 ELSE 0 END AS const_desired_10  -- 衛生設備施工管理
            , CASE WHEN desired_occupation__c IS NULL THEN 0 WHEN desired_occupation__c LIKE '%プラント施工管理%' THEN 1 ELSE 0 END AS const_desired_11  -- プラント施工管理
            , CASE WHEN desired_occupation__c IS NULL THEN 0 WHEN desired_occupation__c LIKE '%計装%' THEN 1 ELSE 0 END AS const_desired_12            -- 計装
            , CASE WHEN desired_occupation__c IS NULL THEN 0 WHEN desired_occupation__c LIKE '%その他%' THEN 1 ELSE 0 END AS const_desired_13          -- その他
        FROM contact_month_occupation_area
        )

--最終集計
SELECT
    *
FROM entrance;
-- marketing_edit_v2.01_02_entrance_edit_accumulated



-- marketing_edit_v2.01_04_01_record_preprocessed
    -- 更新日：2026/07/17
    -- 作業者：細江
    -- 更新内容：タイムアウト（DEADLINE_EXCEEDED）エラーに伴うリファクタリング

/*
■実行内容
KPI集計ロジックに則り、前回登録から3カ月以上離れているレコードであるかを「通常KPI用」に動的に判定する(前回と今回のレコードを月単位で丸めた場合に、3ヵ月以上離れているか判定する)
また、インシデント等によりKPI集計対象外となるレコードを除外する
cd__c, contact_date により一意
*/

-- 関数定義 (※21年頃に定義されたロジックのため、必要に応じて elapsedDay > 85 等の妥当性を検証したほうが良いか？)
CREATE TEMP FUNCTION func1_bulk(dates ARRAY<DATE>)
    RETURNS ARRAY<BOOL> 
    LANGUAGE js AS r"""
    if (!dates || dates.length === 0) return [];
    let results = [];
    let lastActiveDate = dates[0];
    results.push(true); // 初回は必ず集計対象
    
    for (let i = 1; i < dates.length; i++) {
        const elapsedDay = (dates[i].getTime() - lastActiveDate.getTime()) / 1000 / 60 / 60 / 24;
        if (elapsedDay > 85) {
            lastActiveDate = dates[i];
            results.push(true);
        } else {
            results.push(false);
        }
    }
    return results;
    """;
    
CREATE OR REPLACE TABLE `tryt-bigquery-pj.marketing_edit_v2.01_04_01_record_preprocessed` PARTITION BY contact_date CLUSTER BY occupation AS 
WITH 
    snap_shot1 AS (
        SELECT
            run_date AS insert_date
            ,* EXCEPT(followupchangeddate__c, person_contact_id, import_type__c, run_date)
        FROM `tryt-bigquery-pj.marketing_edit_v2.01_02_entrance_edit_accumulated`
        WHERE 
            contact_month1 >= DATE_ADD(DATE_TRUNC(run_date, MONTH) , INTERVAL -2 MONTH) -- 【注意】25年6月まで運用していた"snap_shot_master"というスナップショットの取得方法と平仄を合わせるため、接触日から3か月間に限定
        ),

    snap_shot2 AS (
        SELECT
            *
        FROM snap_shot1 AS t1  
        WHERE NOT EXISTS -- ★★★★★インシデント等により不要なレコードが混入する場合があるため、それらのレコードを除外する　※各事象の具体は書き残せないが、事象が発生する度に都度社内関係者と協議し、条件追加すること★★★★★
            (
                SELECT
                    *
                FROM
                    (    
                        SELECT
                            j.cd__c
                            , e.saitourokubiseokeiyu__c
                        FROM `tryt-bigquery-pj.marketing_edit_v2.job_seekers_excluded_240507` e --保育のお仕事DRの登録者で「再登録日（SEO経由）」が上書きされた除外対象者のリスト
                        LEFT JOIN `tryt-bigquery-pj.marketing_edit_v2.01_00_career_account_job_seeker_temp_field` j
                            ON e.id = j.id
                    ) e2
                WHERE t1.cd__c = e2.cd__c
                    AND t1.saitourokubiseokeiyu__c = e2.saitourokubiseokeiyu__c
            )
        ),

    record_unique1 AS ( -- 同一SFID、同一接触月のレコードの中で、最も早い接触日かつ最も直近のバッチ処理日のレコードを抽出
        SELECT
            * EXCEPT(insert_date)
            , CURRENT_DATE('Asia/Tokyo') - 1 AS cutoff_date1 -- ★★★〆日項目を作成
        FROM snap_shot2
        QUALIFY ROW_NUMBER() OVER(PARTITION BY cd__c, contact_month1 ORDER BY contact_date ASC, insert_date DESC) = 1
        ),

    record_unique2 AS ( -- UDFバルク処理によるフラグ付与
        SELECT -- cd__cがNULLのものはそのままTRUEとする
            t.*
            , TRUE AS flg
        FROM record_unique1 t
        WHERE cd__c IS NULL
        UNION ALL
        SELECT -- cd__cが存在するものは配列化して一括判定後、OFFSETを利用して直接参照で元に戻す
            r.*
            , flgs[SAFE_OFFSET(pos1)] AS flg
        FROM (
            SELECT 
                cd__c, 
                ARRAY_AGG(t ORDER BY contact_month1 ASC, contact_date ASC) AS arr_rows, 
                func1_bulk(ARRAY_AGG(contact_month1 ORDER BY contact_month1 ASC, contact_date ASC)) AS flgs
            FROM record_unique1 t
            WHERE cd__c IS NOT NULL
            GROUP BY cd__c
        ),
        UNNEST(arr_rows) AS r WITH OFFSET pos1
    )

        /*
            同一sfidに対して複数の登録日のレコードがある場合、前回の集計対象のレコードに対して、当該のレコードの登録日が3ヵ月以上離れている場合、集計対象となる
            ex)
                2024/1/9 登録 →月単位で丸めると2024/1/1 →初回登録のため集計対象
                2024/5/24 再登録 →月単位で丸めると2024/5/1→前回の集計対象登録日を丸めた日付(2024/1/1)との日数差分が3ヵ月経過しているため集計対象
                2024/6/4 再登録 →月単位で丸めると2024/6/1→前回の集計対象登録日を丸めた日付(2024/5/1)との日数差分が3ヵ月経過していないので対象外
                2024/7/31 再登録 →月単位で丸めると2024/7/1→前回の集計対象登録日を丸めた日付(2024/5/1)との日数差分が3ヵ月経過していないので対象外
                2024/10/22 再登録 →月単位で丸めると2024/10/1→前回の集計対象登録日を丸めた日付(2024/5/1)との日数差分が3ヵ月経過しているため集計対象
                2024/11/13 再登録 →月単位で丸めると2024/11/1→前回の集計対象登録日を丸めた日付(2024/10/1)との日数差分が3ヵ月経過していないので対象外
        */

--最終集計
SELECT 
    *
FROM record_unique2;
-- marketing_edit_v2.01_04_01_record_preprocessed



-- marketing_edit_v2.01_04_02_record_preprocessed
    -- 更新日：2025/10/20
    -- 作業者：K.ISOZUMI
    -- 更新内容：パーティショニングの設定

/*
■実行内容
施工管理の再登録時において、適切にutm情報が更新されなかった事象が2021年頃に発生したと思われ、それらの不要なレコードを除外する
また、「国家試験」などの除外するべきレコードを処理し、KPI判定に関する細かい情報（新規/1年以内再登録/1年以上再登録 等）を整理
cd__c, contact_date により一意
*/

CREATE OR REPLACE TABLE `tryt-bigquery-pj.marketing_edit_v2.01_04_02_record_preprocessed` PARTITION BY contact_month1 AS 
WITH 
    ad_rere AS ( -- 施工管理の広告経路における再登録レコードを特定するための整理
        SELECT
            *
            , ROW_NUMBER() OVER(PARTITION BY cd__c ORDER BY contact_date ASC) AS rn
        FROM `tryt-bigquery-pj.marketing_edit_v2.01_04_01_record_preprocessed`
        WHERE occupation = '施工管理'
        ),

    ad_rere_judge AS ( -- 各レコードに対して、前回の接触（登録）情報を突合
        SELECT
            t1.* EXCEPT(flg , rn)
            , CASE 
                WHEN t1.rn = 1 THEN TRUE -- 新規登録は問題なし
                ELSE 
                    CASE 
                        WHEN IFNULL(t1.utmsource__c_not_first, '') = IFNULL(t2.utmsource__c_not_first, '')
                            AND IFNULL(t1.utmmedium__c_not_first, '') = IFNULL(t2.utmmedium__c_not_first, '')
                            AND IFNULL(t1.utmcampaign__c, '') = IFNULL(t2.utmcampaign__c, '')
                            AND IFNULL(t1.utmcontent__c, '') = IFNULL(t2.utmcontent__c, '')
                            AND IFNULL(t1.utmterm__c, '') = IFNULL(t2.utmterm__c, '')
                                THEN FALSE -- 前回接触時とutm情報が一致していれば、情報が更新されていない可能性があるため、除外対象として判定する
                        ELSE TRUE
                    END 
            END AS ad_flg
        FROM ad_rere AS t1
        LEFT JOIN ad_rere AS t2
            ON t1.cd__c = t2.cd__c
                AND t1.rn = t2.rn + 1
        WHERE t1.flg = TRUE -- 前回の集計対象のレコードに対して、当該のレコードの登録日が3ヵ月以上離れておりKPI集計対象である
        ),

    record_unique AS ( -- 施工管理において接触判定がTRUEのレコードと、その他職種におけるレコードを抽出
        SELECT
            t1.* EXCEPT(flg)
        FROM `tryt-bigquery-pj.marketing_edit_v2.01_04_01_record_preprocessed` AS t1
        LEFT JOIN ad_rere_judge AS t2
            ON t1.cd__c = t2.cd__c
                AND t1.contact_date = t2.contact_date
        WHERE t1.flg = TRUE -- 前回の集計対象のレコードに対して、当該のレコードの登録日が3ヵ月以上離れておりKPI集計対象である
            AND CASE 
                    WHEN t1.occupation = '施工管理' THEN t2.ad_flg 
                    ELSE TRUE 
                END = TRUE -- 施工管理において処理されたレコードと、その他職種におけるKPI集計対象要件（期間）を満たすレコードのみを抽出
        ),

    column_edit1 AS ( -- 入口の項目を整形
        SELECT
            t1.* EXCEPT(utmcampaign__c)                                                
            , CASE 
                WHEN t1.occupation <> '施工管理' AND t1.judge_entry_route LIKE '%新規%' THEN t2.utmsource_first__c  -- 紹介事業で新規登録の場合は、career_account_job_seeker.utmsource_first__c
                ELSE t1.utmsource__c_not_first -- それ以外の場合は、career_account_job_seeker.utmsource__c
            END AS utmsource__c -- ★★★★★★★★★★★★ 求職者OBJの段階で不具合が頻発するカラム、名称は統合されたものであるため要注意 ★★★★★★★★★★★★
            , CASE 
                WHEN t1.occupation <> '施工管理' AND t1.judge_entry_route LIKE '%新規%' THEN t2.utmmedium_first__c  -- 紹介事業で新規登録の場合は、career_account_job_seeker.utmmedium_first__c
                ELSE t1.utmmedium__c_not_first -- それ以外の場合は、career_account_job_seeker.utmmedium__c
            END AS utmmedium__c -- ★★★★★★★★★★★★ 求職者OBJの段階で不具合が頻発するカラム、名称は統合されたものであるため要注意 ★★★★★★★★★★★★
            , CASE 
                WHEN t1.occupation <> '施工管理' AND t1.judge_entry_route LIKE '%新規%' THEN t2.utmcampaign_first__c 
                ELSE t1.utmcampaign__c 
            END AS utmcampaign__c
            , CASE 
                WHEN t1.occupation = '技師' AND t1.yuusensikakusyuukeiyou__c LIKE '%診療放射線技師%' THEN 
                    CASE 
                        WHEN t2.comment_on_entry__c LIKE '%マンモ%' THEN 'マンモ経験者' 
                        ELSE 'マンモ未経験者' 
                    END
                ELSE NULL 
            END AS rt_flg
            , CASE 
                WHEN t1.occupation = '技師' AND t1.yuusensikakusyuukeiyou__c LIKE '%臨床検査技師%' THEN 
                    CASE 
                        WHEN t2.comment_on_entry__c LIKE '%超音波%' OR t2.comment_on_entry__c LIKE '%エコー%' THEN 'エコー経験者' 
                        ELSE 'エコー未経験者' 
                    END
                ELSE NULL 
            END AS mt_flg
        FROM record_unique AS t1
        LEFT JOIN `tryt-bigquery-pj.marketing_edit_v2.01_00_career_account_job_seeker_temp_field` AS t2
            ON t1.cd__c = t2.cd__c
        ),

    column_edit2 AS ( -- 入口の項目を整形
        SELECT
            *
            , CONCAT(utmsource__c,utmmedium__c) AS utm_source_medium
            , CONCAT(utmcampaign__c,utmterm__c) AS utm_campaign_term
        FROM column_edit1
      ),

    utm_set AS ( -- 「国試除外」/「ワクチン整形」などの経路情報を修正するために、utmパラメータ整理用マスタの情報を整形
        SELECT DISTINCT 
            CONCAT(CONCAT(CONCAT(IFNULL(utm_source, ''), IFNULL(utm_medium, '')), IFNULL(utm_campaign, '')), IFNULL(utm_term, '')) AS parameter
            , category
            , occupation
            , CASE 
                WHEN CONCAT(utm_source,utm_medium) IS NOT NULL THEN 's-m'
                WHEN utm_source IS NOT NULL THEN 's'
                WHEN CONCAT(utm_campaign,utm_term) IS NOT NULL THEN 'c-t'
                WHEN utm_campaign IS NOT NULL THEN 'c'
                WHEN utm_term IS NOT NULL THEN 't'
                ELSE NULL 
            END AS utm_set
            , CONCAT(utm_source,utm_medium) AS utm_source_medium
            , CONCAT(utm_campaign,utm_term) AS utm_campaign_term
            , utm_source
            , utm_medium
            , utm_campaign
            , utm_term
        FROM `tryt-bigquery-pj.production_tryt.master_utm_set` -- パラメータ整理用マスタ https://docs.google.com/spreadsheets/d/12Avh9jaKAmKUqoZpzVR3HzIIOHu6A4U8MdJQn82AuSM/edit?gid=0#gid=0
        ),

    entry_route_edit AS ( -- 流入経路用分類において、除外予定分の処理を行う(「広告経由」として分類されてしまうところ「その他」として分類する)
        SELECT
            t1.* EXCEPT(entry_route , utm_source_medium , utm_campaign_term)
            , ROW_NUMBER() OVER(PARTITION BY t1.cd__c ORDER BY t1.contact_date ASC) AS rn
            , CASE 
                WHEN 
                    CASE 
                        WHEN t2.category = '国家試験' OR t3.category = '国家試験' OR t4.category = '国家試験' OR t5.category = '国家試験' OR t6.category = '国家試験' THEN 1 
                        ELSE 0 
                    END = 1 
                        THEN 'その他' -- 国試は除外
                WHEN t1.entry_route = '広告' 
                    AND 
                        (
                            (
                                (t2.category = 'ワクチン' OR t3.category = 'ワクチン' OR t4.category = 'ワクチン' OR t5.category = 'ワクチン' OR t6.category = 'ワクチン')
                                AND 
                                (t1.contact_date <= DATE('2021-07-12') OR t1.contact_date BETWEEN DATE('2022-05-01') AND DATE('2022-05-31')) -- 過去の特定時点におけるワクチン配信は広告集計対象外
                            )
                            OR (t1.utmsource__c = 'crm_MailMag' AND t1.utmmedium__c = 'email') -- メルマガ
                            OR (t1.utmsource__c = 'mailmagazine' AND t1.utmmedium__c = 'crm') -- メルマガ
                            OR (t1.utmsource__c = 'MailMag' AND t1.utmmedium__c IS NULL) -- メルマガ
                            OR (t1.utmsource__c = 'crm_sms' AND t1.utmmedium__c = 'sms') -- SMS
                            OR (t1.utmsource__c = 'crm_sms' AND t1.utmmedium__c IS NULL) -- SMS
                            OR (t1.utmsource__c = 'facebook' AND t1.utmmedium__c = 'CRM') -- facebook
                            OR (t1.utmsource__c = 'twitter' AND t1.utmmedium__c = 'message') -- twitter
                            OR (t1.utmsource__c = 'sms' AND t1.utmmedium__c LIKE 'cs%') -- CS
                            OR (t1.utmsource__c = 'sms' AND t1.utmmedium__c LIKE 'is%') -- IS
                            OR (t1.utmsource__c = 'im' AND t1.utmmedium__c = 'cpc') -- '不明'
                            OR (t1.utmsource__c = 'leafle' AND t1.utmmedium__c = 'qr') -- '不明'
                            OR (t1.utmsource__c = 'mememe-kizon-source' AND t1.utmmedium__c = 'mememe-kizon-medium') -- '不明'
                            OR (t1.utmsource__c = 'optimize' AND t1.utmmedium__c = 'optimize') -- '不明'
                            OR (t1.utmsource__c = 'sales' AND t1.utmmedium__c = 'sales') -- '不明'
                            OR (t1.utmsource__c = 'school' AND t1.utmmedium__c = 'qr') -- '不明'
                            OR (t1.utmsource__c = 'zalo' AND t1.utmmedium__c = 'zalo') -- '不明'
                            OR (t1.utmsource__c = '27745' AND t1.utmmedium__c IS NULL) -- '不明'
                            OR (t1.utmsource__c = 'fanpat' AND t1.utmmedium__c IS NULL) -- '不明'
                            OR (t1.utmsource__c = 'kjs' AND t1.utmmedium__c IS NULL) -- '不明'
                            OR (t1.utmsource__c = 'sales' AND t1.utmmedium__c IS NULL) -- '不明'
                            OR (t1.utmsource__c = 'sms_pj' AND t1.utmmedium__c IS NULL) -- '不明'
                            OR (t1.utmsource__c IS NULL AND t1.utmmedium__c = 'CRM') -- '不明'
                            OR (t1.utmsource__c IS NULL AND t1.utmmedium__c = 'organic') -- '不明'
                            OR (t1.utmsource__c IS NULL AND t1.utmmedium__c = 'referral') -- '不明'
                            OR (t1.utmsource__c IS NULL AND t1.utmmedium__c = 'social') -- '不明'
                        )
                THEN 'その他'  
                ELSE t1.entry_route 
            END AS entry_route
            , CASE 
                WHEN t1.entry_route = '広告' AND (t2.category = 'ワクチン' OR t3.category = 'ワクチン' OR t4.category = 'ワクチン' OR t5.category = 'ワクチン' OR t6.category = 'ワクチン') THEN 'ワクチン流入' 
                ELSE '通常' 
            END AS vaccine_flg
        FROM column_edit2 AS t1
        LEFT JOIN utm_set AS t2
            ON t2.utm_set = 's-m'
                AND t1.utm_source_medium = t2.utm_source_medium
                AND t1.occupation = t2.occupation
        LEFT JOIN utm_set AS t3
            ON t3.utm_set = 's'
                AND t1.utmsource__c = t3.utm_source
                AND t1.occupation = t3.occupation
        LEFT JOIN utm_set AS t4
            ON t4.utm_set = 'c-t'
                AND t1.utm_campaign_term = t4.utm_campaign_term
                AND t1.occupation = t4.occupation
        LEFT JOIN utm_set AS t5
            ON t5.utm_set = 'c'
                AND t1.utmcampaign__c = t5.utm_campaign
                AND t1.occupation = t5.occupation
        LEFT JOIN utm_set AS t6
            ON t6.utm_set = 't'
                AND t1.utmterm__c = t6.utm_term
                AND t1.occupation = t6.occupation
        ),

    rere_judge1 AS ( -- KPI集計の細かい情報（新規/1年以内再登録/1年以上再登録 等）を判別
        SELECT
            t1.* EXCEPT(rn)
            , CASE 
                WHEN t1.rn = 1 THEN 
                    CASE 
                        WHEN t1.contact_date = t1.registration_date__c_for_calculation THEN '新規'
                        ELSE 
                            CASE 
                                WHEN t1.contact_date >= DATE_ADD(t1.registration_date__c_for_calculation , INTERVAL 12 MONTH) THEN '1年以上' 
                                ELSE '1年以内' 
                            END
                    END
                ELSE 
                    CASE
                        WHEN t1.contact_date >= DATE_ADD(t2.contact_date , INTERVAL 12 MONTH) THEN '1年以上' 
                        ELSE '1年以内' 
                    END
            END AS flg
        FROM entry_route_edit AS t1
        LEFT JOIN entry_route_edit AS t2
            ON t1.cd__c = t2.cd__c
                AND t1.rn = t2.rn + 1
        ),

    rere_judge2 AS ( -- 前テーブルの判定に基づき、項目情報を整理
        SELECT
            * EXCEPT(flg, judge_entry_route)
            , CASE 
                WHEN flg = '新規' THEN 
                    CASE 
                        WHEN entry_route = 'その他' THEN 'その他新規登録' 
                        ELSE judge_entry_route 
                    END
                WHEN flg = '1年以上' THEN 
                    CASE 
                        WHEN entry_route = '広告' THEN '広告1年以上再登録'
                        WHEN entry_route = 'フルファネル' THEN 'フルファネル1年以上再登録'
                        WHEN entry_route = 'SEO' THEN 'SEO1年以上再登録'
                        WHEN entry_route = 'その他' THEN 'その他1年以上再登録'
                        WHEN judge_entry_route = 'CRM（LINE）再登録' THEN 'CRM（LINE）1年以上再登録'
                        WHEN judge_entry_route = 'CRM（友人紹介）再登録' THEN 'CRM（友人紹介）1年以上再登録'
                        ELSE judge_entry_route 
                    END
                WHEN flg = '1年以内' THEN 
                    CASE 
                        WHEN entry_route = '広告' THEN '広告1年以内再登録'
                        WHEN entry_route = 'フルファネル' THEN 'フルファネル1年以内再登録'
                        WHEN entry_route = 'SEO' THEN 'SEO1年以内再登録'
                        WHEN entry_route = 'その他' THEN 'その他1年以内再登録'
                        WHEN judge_entry_route = 'CRM（LINE）再登録' THEN 'CRM（LINE）1年以内再登録'
                        WHEN judge_entry_route = 'CRM（友人紹介）再登録' THEN 'CRM（友人紹介）1年以内再登録'
                        ELSE judge_entry_route 
                    END
                ELSE judge_entry_route 
            END AS judge_entry_route
        FROM rere_judge1
        )

--最終集計
SELECT
    *
FROM rere_judge2;
-- marketing_edit_v2.01_04_02_record_preprocessed



-- marketing_edit_v2.01_10_01_reregistration_rank
    -- 更新日：2025/10/20
    -- 作業者：K.ISOZUMI
    -- 更新内容：パーティショニングの設定

/*
■実行内容
月別/再登録経路別に集計を残すための整形を行う
主にはCRM再登録としてのKPI集計に活用
(PK：不明)
*/

CREATE OR REPLACE TABLE `tryt-bigquery-pj.marketing_edit_v2.01_10_01_reregistration_rank` PARTITION BY saitourokubisyukeiyou__c_for_calculation AS 
WITH 
    re_record1 AS ( -- 再登録レコードの抽出
        SELECT
            run_date AS insert_date
            ,* EXCEPT(followupchangeddate__c, person_contact_id, import_type__c, run_date)
            , DATE_TRUNC(saitourokubi_adkeiyu__c_for_calculation , MONTH) AS reregistration_month_ad
            , DATE_TRUNC(saitourokubigaibukeiyu__c_for_calculation , MONTH) AS reregistration_month_gaibu
            , DATE_TRUNC(saitourokubiseokeiyu__c_for_calculation , MONTH) AS reregistration_month_seo
            , DATE_TRUNC(saitourokubisyukeiyou__c_for_calculation , MONTH) AS reregistration_month_crm
        FROM `tryt-bigquery-pj.marketing_edit_v2.01_02_entrance_edit_accumulated`
        WHERE       -- 【注意】25年6月まで運用していた"snap_shot_master"というスナップショットの取得方法と平仄を合わせるため、接触日から7日間に限定
            saitourokubi_adkeiyu__c_for_calculation >= run_date - 7
            OR saitourokubigaibukeiyu__c_for_calculation >= run_date - 7
            OR saitourokubiseokeiyu__c_for_calculation >= run_date - 7
            OR saitourokubisyukeiyou__c_for_calculation >= run_date - 7
        ),

    re_record2 AS ( -- 不要なレコードを除外
        SELECT
            *
        FROM re_record1 t1
        WHERE NOT EXISTS -- ★★★★★インシデント等により不要なレコードが混入する場合があるため、それらのレコードを除外する　※各事象の具体は書き残せないが、事象が発生する度に都度社内関係者と協議し、条件追加すること★★★★★
            (
                SELECT
                    *
                FROM
                    (    
                        SELECT
                            j.cd__c
                            , e.saitourokubiseokeiyu__c
                        FROM `tryt-bigquery-pj.marketing_edit_v2.job_seekers_excluded_240507` e --保育のお仕事DRの登録者で「再登録日（SEO経由）」が上書きされた除外対象者のリスト
                        LEFT JOIN `tryt-bigquery-pj.marketing_edit_v2.01_00_career_account_job_seeker_temp_field` j
                            ON e.id = j.id
                    ) e2
                WHERE t1.cd__c = e2.cd__c
                    AND t1.saitourokubiseokeiyu__c = e2.saitourokubiseokeiyu__c
            )
        ),

    re_rank AS ( -- それぞれの登録項目において、月単位でユニークに集計を行うために整形を行う また項目情報と名称を調整
        SELECT
            t1.* EXCEPT(utmcampaign__c)
            , ROW_NUMBER() OVER(PARTITION BY t1.cd__c, t1.reregistration_month_crm ORDER BY t1.saitourokubisyukeiyou__c_for_calculation ASC, t1.insert_date DESC) AS rank_crm
            , CASE 
                WHEN t1.occupation <> '施工管理' AND t1.judge_entry_route LIKE '%新規%' THEN t2.utmsource_first__c 
                ELSE t1.utmsource__c_not_first 
            END AS utmsource__c
            , CASE 
                WHEN t1.occupation <> '施工管理' AND t1.judge_entry_route LIKE '%新規%' THEN t2.utmmedium_first__c 
                ELSE t1.utmmedium__c_not_first 
            END AS utmmedium__c
            , CASE 
                WHEN t1.occupation <> '施工管理' AND t1.judge_entry_route LIKE '%新規%' THEN t2.utmcampaign_first__c 
                ELSE t1.utmcampaign__c 
            END AS utmcampaign__c
            , CASE 
                WHEN t1.occupation = '技師' AND t1.yuusensikakusyuukeiyou__c LIKE '%診療放射線技師%' THEN 
                    CASE 
                        WHEN t2.comment_on_entry__c LIKE '%マンモ%' THEN 'マンモ経験者' 
                        ELSE 'マンモ未経験者' 
                    END 
                ELSE NULL 
            END AS rt_flg
            , CASE 
                WHEN t1.occupation = '技師' AND t1.yuusensikakusyuukeiyou__c LIKE '%臨床検査技師%' THEN 
                    CASE 
                        WHEN t2.comment_on_entry__c LIKE '%超音波%' OR t2.comment_on_entry__c LIKE '%エコー%' THEN 'エコー経験者' 
                        ELSE 'エコー未経験者' 
                    END 
                ELSE NULL 
            END AS mt_flg
        FROM re_record2 AS t1
        LEFT JOIN `tryt-bigquery-pj.marketing_edit_v2.01_00_career_account_job_seeker_temp_field` AS t2
            ON t1.cd__c = t2.cd__c
        WHERE t1.cd__c IS NOT NULL
        )

--最終集計
SELECT 
    *
FROM re_rank;
-- marketing_edit_v2.01_10_01_reregistration_rank



-- marketing_edit_v2.01_11_01_nu_rank
    -- 更新日：2025/7/11
    -- 作業者：K.ISOZUMI
    -- 更新内容：ソース変更

/*
■実行内容
NUに連携された求職者に関して、NU連携の情報上書きを回避するための処理を行う
月毎に営業⇒NU連携のレコードを整理し、NU連携以降のミュート、営業連携情報を突合する
(cd__c, followupchangeddate__cにより一意)
*/

CREATE OR REPLACE TABLE `tryt-bigquery-pj.marketing_edit_v2.01_11_01_nu_rank` AS 
WITH 
    nu_record1 AS ( -- nuレコードの抽出
        SELECT
            t1.run_date AS insert_date
            , t1.* EXCEPT(followupchangeddate__c, person_contact_id, import_type__c, run_date, temp_id)
            , t1.followupchangeddate__c -- NU対象変更日
            , CASE 
                WHEN t1.occupation <> '施工管理' THEN DATE(t2.nu_sales_collaboration_date__c) 
                WHEN t1.occupation = '施工管理' THEN NULL 
                ELSE NULL 
            END AS nusalescollaborationdate__pc --【NU】営業連携日
            , CASE 
                WHEN t1.occupation <> '施工管理' THEN DATE(t2.nu_mute_day__c) 
                WHEN t1.occupation = '施工管理' THEN NULL 
                ELSE NULL 
            END AS numuteday__pc --【NU】ミュート日
        FROM 
            (
                SELECT
                    *
                    ,ROW_NUMBER()OVER(ORDER BY cd__c, run_date, contact_date) AS temp_id
                FROM `tryt-bigquery-pj.marketing_edit_v2.01_02_entrance_edit_accumulated`
            ) AS t1
        LEFT JOIN `tryt-bigquery-pj.marketing_edit_v2.02_00_career_contact_accumulated_temp_field` AS t2
            ON t1.person_contact_id = t2.id
                AND t1.run_date >= t2.run_date
                AND t1.occupation <> '施工管理'
        QUALIFY
            ROW_NUMBER()OVER(PARTITION BY t1.temp_id ORDER BY t2.run_date DESC, t2.last_modified_date DESC) = 1
        ),

    nu_record2 AS ( -- 不要なレコードを除外 
        SELECT
            *
            , DATE_TRUNC(followupchangeddate__c , MONTH) AS followupchangedmonth__pc            -- NU対象変更日 を月単位で丸める
            , DATE_TRUNC(nusalescollaborationdate__pc , MONTH) AS nusalescollaborationmonth__pc --【NU】営業連携日 を月単位で丸める
            , DATE_TRUNC(numuteday__pc , MONTH) AS numutemonth__pc                              --【NU】ミュート日 を月単位で丸める
        FROM nu_record1 AS t1
        WHERE NOT EXISTS -- ★★★★★インシデント等により不要なレコードが混入する場合があるため、それらのレコードを除外する　※各事象の具体は書き残せないが、事象が発生する度に都度社内関係者と協議し、条件追加すること★★★★★
            (
                SELECT
                    *
                FROM
                    (    
                        SELECT
                            j.cd__c
                            , e.saitourokubiseokeiyu__c
                        FROM `tryt-bigquery-pj.marketing_edit_v2.job_seekers_excluded_240507` e --保育のお仕事DRの登録者で「再登録日（SEO経由）」が上書きされた除外対象者のリスト
                        LEFT JOIN `tryt-bigquery-pj.marketing_edit_v2.01_00_career_account_job_seeker_temp_field` j
                            ON e.id = j.id
                    ) e2
                WHERE t1.cd__c = e2.cd__c
                    AND t1.saitourokubiseokeiyu__c = e2.saitourokubiseokeiyu__c
            )
        ),

    nu_rank AS ( -- NUに関する各項目において、月毎にユニークに集計するための準備を行う
        SELECT
            *
            , ROW_NUMBER() OVER(PARTITION BY cd__c, followupchangedmonth__pc ORDER BY followupchangeddate__c /*NU対象変更日*/ ASC, insert_date DESC) AS rank_followupchanged
            , CASE 
                WHEN nusalescollaborationdate__pc IS NULL THEN NULL
                ELSE ROW_NUMBER() OVER(PARTITION BY cd__c, nusalescollaborationmonth__pc ORDER BY nusalescollaborationdate__pc /*【NU】営業連携日*/ ASC, followupchangeddate__c ASC, insert_date DESC) 
            END AS rank_nusalescollaboration
            , CASE 
                WHEN numuteday__pc IS NULL THEN NULL
                ELSE ROW_NUMBER() OVER(PARTITION BY cd__c, numutemonth__pc ORDER BY numuteday__pc ASC, followupchangeddate__c ASC, insert_date DESC) 
            END AS rank_numute
        FROM nu_record2
        WHERE cd__c IS NOT NULL 
            AND followupchangeddate__c IS NOT NULL
        ),

    nu_followupchanged1 AS ( -- NU対象のレコードをユニークに集計したテーブルに対して、それ以降のミュート日を突合する
        SELECT
            t1.* EXCEPT(numuteday__pc , numutemonth__pc)
            , t2.numuteday__pc
            , t2.numutemonth__pc
        FROM nu_rank AS t1
        LEFT JOIN nu_rank AS t2
            ON t1.cd__c = t2.cd__c
                AND t1.followupchangeddate__c <= t2.numuteday__pc
                AND t2.rank_numute = 1
        WHERE t1.rank_followupchanged = 1
        QUALIFY 
            ROW_NUMBER() OVER(PARTITION BY t1.cd__c, t1.followupchangedmonth__pc /*NU対象変更月*/ ORDER BY t2.numuteday__pc /*【NU】ミュート日*/ ASC) = 1
        ),

    nu_followupchanged2 AS ( -- NU対象のレコードをユニークに集計したテーブルに対して、それ以降の営業連携日(NU→営業)を突合する ※ミュート日といずれかが入るように調整
        SELECT
            t1.* EXCEPT(followupchangeddate__c , nusalescollaborationdate__pc , numuteday__pc , followupchangedmonth__pc , nusalescollaborationmonth__pc , numutemonth__pc)
            , t1.followupchangeddate__c

            -- mute → 営業連携はNULLとする 
            , CASE 
                WHEN t1.numuteday__pc < t2.nusalescollaborationdate__pc THEN NULL 
                ELSE t2.nusalescollaborationdate__pc 
            END AS nusalescollaborationdate__pc -- 【NU】営業連携日

            -- 営業連携 → mute はNULLとする
            , CASE 
                WHEN t1.numuteday__pc >= t2.nusalescollaborationdate__pc THEN NULL 
                ELSE t1.numuteday__pc 
            END AS numuteday__pc
            , t1.followupchangedmonth__pc  --【NU】ミュート日
            , CASE 
                WHEN t1.numuteday__pc < t2.nusalescollaborationdate__pc THEN NULL 
                ELSE t2.nusalescollaborationmonth__pc 
            END AS nusalescollaborationmonth__pc
            , CASE 
                WHEN t1.numuteday__pc >= t2.nusalescollaborationdate__pc THEN NULL 
                ELSE t1.numutemonth__pc 
            END AS numutemonth__pc     
        FROM nu_followupchanged1 AS t1
        LEFT JOIN nu_rank AS t2
            ON t1.cd__c = t2.cd__c
                AND t1.followupchangeddate__c <= t2.nusalescollaborationdate__pc -- NU対象変更日 <=【NU】営業連携日
                AND t2.rank_nusalescollaboration = 1
        QUALIFY
            ROW_NUMBER() OVER(PARTITION BY t1.cd__c , t1.followupchangedmonth__pc /*NU対象変更月*/ ORDER BY t2.nusalescollaborationdate__pc /*【NU】営業連携日*/ ASC) = 1
        ),

    nu_followupchanged3 AS ( -- レコードの重複を回避するために、同一ミュート日に着目してレコードをユニークに集計する
        SELECT
            *
        FROM nu_followupchanged2
        QUALIFY
            CASE 
                WHEN numuteday__pc IS NULL THEN 1 
                ELSE ROW_NUMBER() OVER(PARTITION BY cd__c , numuteday__pc ORDER BY followupchangeddate__c ASC) 
            END = 1
        ),

    nu_followupchanged4 AS ( -- レコードの重複を回避するために、同一の営業連携日に着目してレコードをユニークに集計する
        SELECT
            *
        FROM nu_followupchanged3
        QUALIFY
            CASE 
                WHEN nusalescollaborationdate__pc IS NULL THEN 1 
                ELSE ROW_NUMBER() OVER(PARTITION BY cd__c , nusalescollaborationdate__pc ORDER BY followupchangeddate__c ASC) 
            END = 1
        ),

    nu_followupchanged5 AS ( -- ミュート日、営業連携日ともにNULLであるにも関わらず、再度営業連携されているケースの除外用
        SELECT
            *
        FROM nu_followupchanged4
        WHERE 
            numuteday__pc IS NULL 
            AND nusalescollaborationdate__pc IS NULL
        QUALIFY
            ROW_NUMBER() OVER(PARTITION BY cd__c ORDER BY followupchangeddate__c ASC) > 1
        ),

    entrance_info AS ( -- 入口の項目を整理
        SELECT
            t1.* EXCEPT(utmcampaign__c , rank_followupchanged , rank_nusalescollaboration , rank_numute)
            , CASE 
                WHEN t1.occupation <> '施工管理' AND t1.judge_entry_route LIKE '%新規%' THEN t2.utmsource_first__c 
                ELSE t1.utmsource__c_not_first
            END AS utmsource__c
            , CASE 
                WHEN t1.occupation <> '施工管理' AND t1.judge_entry_route LIKE '%新規%' THEN t2.utmmedium_first__c 
                ELSE t1.utmmedium__c_not_first 
            END AS utmmedium__c
            , CASE 
                WHEN t1.occupation <> '施工管理' AND t1.judge_entry_route LIKE '%新規%' THEN t2.utmcampaign_first__c 
                ELSE t1.utmcampaign__c 
            END AS utmcampaign__c
            , CASE 
                WHEN t1.occupation = '技師' AND t1.yuusensikakusyuukeiyou__c LIKE '%診療放射線技師%' THEN 
                    CASE 
                        WHEN t2.comment_on_entry__c LIKE '%マンモ%' THEN 'マンモ経験者' 
                        ELSE 'マンモ未経験者' 
                    END 
                ELSE NULL 
            END AS rt_flg
            , CASE 
                WHEN t1.occupation = '技師' AND t1.yuusensikakusyuukeiyou__c LIKE '%臨床検査技師%' THEN 
                    CASE 
                        WHEN t2.comment_on_entry__c LIKE '%超音波%' OR t2.comment_on_entry__c LIKE '%エコー%' THEN 'エコー経験者' 
                        ELSE 'エコー未経験者' 
                    END 
                ELSE NULL 
            END AS mt_flg
        FROM nu_followupchanged4 AS t1
        LEFT JOIN `tryt-bigquery-pj.marketing_edit_v2.01_00_career_account_job_seeker_temp_field` AS t2
            ON t1.cd__c = t2.cd__c
        WHERE NOT EXISTS --ミュート日、営業連携日ともにNULLであるにも関わらず、営業連携されているケースを除外
            (
                SELECT
                    *
                FROM nu_followupchanged5 t5
                WHERE t1.cd__c = t5.cd__c
                    AND t1.followupchangeddate__c = t5.followupchangeddate__c
            )        
        )

--最終集計
SELECT 
    *
FROM entrance_info;
-- marketing_edit_v2.01_11_01_nu_rank



-- marketing_edit_v2.01_05_01_record_raw
    -- 更新日：2026/07/17
    -- 作業者：細江
    -- 更新内容：タイムアウト（DEADLINE_EXCEEDED）エラーに伴うリファクタリング

/*
■実行内容
通常KPI+CRM再登録+NU経路を1つのテーブルにユニオンし、入口項目を整形する
【重要】通常KPI+CRM再登録+NU経路がユニオンされているだけなので、経路毎の重複が発生している
(contact_dateがNULLの場合を除き、cd__c と contact_date と judge_entry_route により一意)
*/

CREATE OR REPLACE TABLE `tryt-bigquery-pj.marketing_edit_v2.01_05_01_record_raw` PARTITION BY contact_date CLUSTER BY cd__c AS 
WITH 
    normal_preprocessed AS ( -- 「通常KPI」に関するテーブルを引用
        SELECT *
        FROM `tryt-bigquery-pj.marketing_edit_v2.01_04_02_record_preprocessed`                  -- 接触月が25年7月以降のレコードはaccumulated由来のテーブルから引用する
        WHERE contact_month1 >= DATE "2025-07-01"
        UNION ALL
        SELECT * 
        FROM `tryt-bigquery-pj.marketing_edit_v2.01_04_02_record_preprocessed_past_20250630`    -- 接触月が25年6月以前のレコードは25年6月まで運用していた"snap_shot_master"というスナップショットから取得したテーブルから引用する 【重要】01_04_02_record_preprocessed で項目追加が発生した場合は、pastにおいても当該項目を追加すること
        WHERE contact_month1 <= DATE "2025-06-01"
        ),

    crm_rereg_record AS ( -- CRM再登録に関するテーブルを引用
        SELECT                                                                                  -- 接触月が25年7月以降のレコードはaccumulated由来のテーブルから引用する
            *
        FROM (
                SELECT *
                FROM `tryt-bigquery-pj.marketing_edit_v2.01_10_01_reregistration_rank`
                WHERE 
                    rank_crm = 1                                                                -- 再登録日（CRM経由）の項目を用いてユニークに集計 (PARTITION BY t1.cd__c , t1.reregistration_month_crm ORDER BY t1.saitourokubisyukeiyou__c_for_calculation ASC , t1.insert_date DESC) により生成
                    AND saitourokubisyukeiyou__c_for_calculation >= target_start_date
              )
        WHERE DATE_TRUNC(saitourokubisyukeiyou__c, MONTH) >= DATE "2025-07-01"
        UNION ALL
        SELECT                                                                                  -- 接触月が25年6月以前のレコードは25年6月まで運用していた"snap_shot_master"というスナップショットから取得したテーブルから引用する 【重要】01_10_01_reregistration_rank で項目追加が発生した場合は、pastにおいても当該項目を追加すること
            * 
        FROM (
                SELECT *
                FROM `tryt-bigquery-pj.marketing_edit_v2.01_10_01_reregistration_rank_past_20250630`
                WHERE 
                    rank_crm = 1                                                                -- 再登録日（CRM経由）の項目を用いてユニークに集計 (PARTITION BY t1.cd__c , t1.reregistration_month_crm ORDER BY t1.saitourokubisyukeiyou__c_for_calculation ASC , t1.insert_date DESC) により生成
                    AND saitourokubisyukeiyou__c_for_calculation >= target_start_date
              )
        WHERE DATE_TRUNC(saitourokubisyukeiyou__c, MONTH) <= DATE "2025-06-01"
        ),
        
    crm_rereg_preprocessed AS ( -- CRM再登録に関するレコードを整形
        SELECT
            * EXCEPT(contact_date , contact_month1 , entry_route , judge_entry_route , timing , work_style)
            , CURRENT_DATE('Asia/Tokyo') - 1 AS cutoff_date1                                -- 〆日（昨日〆）修正
            , saitourokubisyukeiyou__c AS contact_date                                      -- 接触日
            , CASE 
                WHEN CURRENT_DATE('Asia/Tokyo') - 1 < saitourokubisyukeiyou__c THEN NULL 
                ELSE DATE_TRUNC(saitourokubisyukeiyou__c , MONTH) 
            END AS contact_month1                                                           -- 接触月
            , 'CRM' AS entry_route                                                          -- 分類
            , CASE 
                WHEN reregisterutmsource__c = 'sms' THEN 'SMS再登録' 
                WHEN reregisterutmsource__c = 'mailmagazine'	THEN 'メルマガ再登録' 
                WHEN reregisterutmsource__c = 'mk_mail' THEN 'Marketo再登録' 
                WHEN reregisterutmsource__c = 'mk_sms' THEN 'MarketoSMS再登録' 
                ELSE 'その他再登録' 
            END AS judge_entry_route                                                        -- 判定
            , CASE 
                WHEN REGEXP_CONTAINS(reregistre_web_requirements__c, '^20(2[6-9]|[3-9][0-9])年4月$') = TRUE THEN reregistre_web_requirements__c -- "20XX年4月"の値が存在する場合
                WHEN REPLACE(UPPER(NORMALIZE(reregistre_web_requirements__c,NFKC)),' ','') IS NULL THEN 'その他'
                WHEN REGEXP_CONTAINS(REPLACE(UPPER(NORMALIZE(reregistre_web_requirements__c,NFKC)),' ',''), '(1ヶ月以内|1ヵ月以内|1ケ月以内|1か月以内|決まり次第)') THEN '1か月以内'
                WHEN REGEXP_CONTAINS(REPLACE(UPPER(NORMALIZE(reregistre_web_requirements__c,NFKC)),' ',''), '(3ヶ月以内|3ヵ月以内|3ケ月以内|3か月以内)') THEN '3か月以内'
                WHEN REGEXP_CONTAINS(REPLACE(UPPER(NORMALIZE(reregistre_web_requirements__c,NFKC)),' ',''), '(6ヶ月以内|6ヵ月以内|6ケ月以内|6か月以内|半年以内)') THEN '6か月以内'
                WHEN REGEXP_CONTAINS(REPLACE(UPPER(NORMALIZE(reregistre_web_requirements__c,NFKC)),' ',''), '(9ヶ月以内|9ヵ月以内|9ケ月以内|9か月以内)') THEN '9か月以内'
                WHEN REGEXP_CONTAINS(REPLACE(UPPER(NORMALIZE(reregistre_web_requirements__c,NFKC)),' ',''), '(12ヶ月以内|12ヵ月以内|12ケ月以内|12か月以内|1年以内)') THEN '1年以内'
                WHEN REPLACE(UPPER(NORMALIZE(reregistre_web_requirements__c,NFKC)),' ','') LIKE '%1年以上%' THEN '1年以上先'
                WHEN REGEXP_CONTAINS(REPLACE(UPPER(NORMALIZE(reregistre_web_requirements__c,NFKC)),' ',''), '(いつでも|すぐにでも|良いところがあれば|よいところがあれば|即日勤務可能)') THEN 'いつでも'
                WHEN REPLACE(UPPER(NORMALIZE(reregistre_web_requirements__c,NFKC)),' ','') LIKE '%未定%' THEN '未定' 
                ELSE 'その他' 
            END AS timing                                                                   -- 希望転職時期 (※整合性は不明なので要注意※)
            , IFNULL(reregistre_web_changehopetime__c, employment_type_shift_pattern1__c) AS work_style -- 希望勤務形態 (※整合性は不明なので要注意※)
        FROM crm_rereg_record
        ),

    normal_crmrereg_integrated AS ( -- 「通常KPI」のレコードとCRM再登録のレコードをユニオン
        SELECT
            jsid
            , cd__c
            , saitourokubigaibukeiyu__c
            , registration_route_fisrst_navi_kaigo__c
            , registration_route_kyuzinzyanal__c
            , registration_route_nursing__c
            , registration_routekaigolila__c
            , registration_route_care_job_navi__c
            , registration_route_fisrst_navi__c
            , registrationroutenurse_e__c
            , registration_route_nurse__c
            , registration_routenasusenka__c
            , registration_route_childcare_job_navi__c
            , registration_routelisujobs__c
            , registration_route_medridgechildcares__c
            , registration_route_nikkei_medicals__c
            , nurseryteachermikata__c
            , registration_route_hoikunooshigoto__c
            , registration_route_eiyoshinooshigoto__c
            , registration_route_friend__c
            , registration_routeyakukyari__c                         -- ※20250116追加
            , age__c
            , yuusensikakusyuukeiyou__c
            , kiboukinmukeitaisyuukei__c
            , employment_type_shift_pattern1__c
            , affiliate_approval_key__c
            , utmsource_first__c
            , reregistre_web_requirements__c
            , reregistre_web_changehopetime__c
            , web_job_application_number__c
            , job_change_time_from__c
            , registration_route_owned_media__c
            , registration_route_external_site__c                    -- ※20241111追加 
            , registration_date__c
            , saitourokubi_adkeiyu__c
            , saitourokubiseokeiyu__c
            , saitourokubisyukeiyou__c
            , dummy_step1_from_js                                    -- 求職者OBJから取得したfirst_hearing__c 
            , dummy_step2_from_js                                    -- 求職者OBJから取得したjob_suggestion__c
            , dummy_step3_from_js                                    -- 求職者OBJから取得したdetermination_of_interview_date__c
            , dummy_step4_from_js                                    -- 求職者OBJから取得したinterview_implementation__c
            , dummy_step5_from_js                                    -- 求職者OBJから取得したagreement__c
            , billing_state
            , branch_text__c
            , department_in_charge__c
            , name
            , owner_id
            , status__c
            , referral_status__c
            , deletion_hope_reason__c
            , web_changehopetime__c
            , utmsource__c_not_first
            , utmmedium__c_not_first
            , utmcampaign__c
            , utmcontent__c
            , utmterm__c
            , reregisterutmsource__c
            , reregisterutmmedium__c
            , reregisterutmcampaign__c
            , reregisterutmcontent__c
            , reregisterutmterm__c
            , gclid__c
            , inflow_route__c
            , reregister_inflow_route__c                            -- 再登録流入経路
            , registration_route01__c
            , registration_route02__c
            , desired_industry__c
            , age_group__c
            , desired_occupation__c
            , experience_in_construction_management__c
            , field_supervisor_experience__c
            , registration_date__c_for_calculation
            , saitourokubi_adkeiyu__c_for_calculation
            , saitourokubigaibukeiyu__c_for_calculation
            , saitourokubiseokeiyu__c_for_calculation
            , saitourokubisyukeiyou__c_for_calculation
            , new_entry_flag                                        -- 新規フラグ
            , contact_date
            , contact_month1
            , branch
            , occupation
            , area
            , entrance_flag                                         -- 入口フラグ(接触数カウントから除外するために活用)
            , experience                                            -- 施工管理経験者
            , young_experience                                      -- 若年層経験者
            , construction_management_experience                    -- 施工管理経験者
            , construction_industry_experience                      -- 施工管理経験有無
            , age_group
            , work_style                                            -- 希望勤務形態
            , timing                                                -- 希望転職時期
            , const_desired_1                                       -- 施工管理における希望職種：建築施工管理
            , const_desired_2                                       -- 施工管理における希望職種：土木施工管理
            , const_desired_3                                       -- 施工管理における希望職種：電気施工管理
            , const_desired_4                                       -- 施工管理における希望職種：電気設備管理
            , const_desired_5                                       -- 施工管理における希望職種：施工図・設計
            , const_desired_6                                       -- 施工管理における希望職種：施工図作成
            , const_desired_7                                       -- 施工管理における希望職種：空調設備施工管理
            , const_desired_8                                       -- 施工管理における希望職種：CADオペレーター
            , const_desired_9                                       -- 施工管理における希望職種：設備施工管理
            , const_desired_10                                      -- 施工管理における希望職種：衛生設備施工管理
            , const_desired_11                                      -- 施工管理における希望職種：プラント施工管理
            , const_desired_12                                      -- 施工管理における希望職種：計装
            , const_desired_13                                      -- 施工管理における希望職種：その他
            , CURRENT_DATE('Asia/Tokyo') - 1 AS cutoff_date1        -- 〆日（昨日〆）修正 ※01_04_02_record_preprocessed_past_20250630`から取得分の〆日が過去の値で固定されてしまっているため、修正を行う(250716 KI追記)
            , utmsource__c
            , utmmedium__c
            , rt_flg
            , mt_flg
            , entry_route
            , judge_entry_route
            , vaccine_flg
            , 2 AS nu_priority_flg                                  -- 営業⇒NU連携における経路優先付けのためのフラグ
        FROM normal_preprocessed
        UNION ALL
        SELECT
            jsid
            , cd__c
            , saitourokubigaibukeiyu__c
            , registration_route_fisrst_navi_kaigo__c
            , registration_route_kyuzinzyanal__c
            , registration_route_nursing__c
            , registration_routekaigolila__c
            , registration_route_care_job_navi__c
            , registration_route_fisrst_navi__c
            , registrationroutenurse_e__c
            , registration_route_nurse__c
            , registration_routenasusenka__c
            , registration_route_childcare_job_navi__c
            , registration_routelisujobs__c
            , registration_route_medridgechildcares__c
            , registration_route_nikkei_medicals__c
            , nurseryteachermikata__c
            , registration_route_hoikunooshigoto__c
            , registration_route_eiyoshinooshigoto__c
            , registration_route_friend__c
            , registration_routeyakukyari__c                         -- ※20250116追加
            , age__c
            , yuusensikakusyuukeiyou__c
            , kiboukinmukeitaisyuukei__c
            , employment_type_shift_pattern1__c
            , affiliate_approval_key__c
            , utmsource_first__c
            , reregistre_web_requirements__c
            , reregistre_web_changehopetime__c
            , web_job_application_number__c
            , job_change_time_from__c
            , registration_route_owned_media__c
            , registration_route_external_site__c                    -- ※20241111追加
            , registration_date__c
            , saitourokubi_adkeiyu__c
            , saitourokubiseokeiyu__c
            , saitourokubisyukeiyou__c
            , dummy_step1_from_js                                    -- 求職者OBJから取得したfirst_hearing__c 
            , dummy_step2_from_js                                    -- 求職者OBJから取得したjob_suggestion__c
            , dummy_step3_from_js                                    -- 求職者OBJから取得したdetermination_of_interview_date__c
            , dummy_step4_from_js                                    -- 求職者OBJから取得したinterview_implementation__c
            , dummy_step5_from_js                                    -- 求職者OBJから取得したagreement__c
            , billing_state
            , branch_text__c
            , department_in_charge__c
            , name
            , owner_id
            , status__c
            , referral_status__c
            , deletion_hope_reason__c
            , web_changehopetime__c
            , utmsource__c_not_first
            , utmmedium__c_not_first
            , utmcampaign__c
            , utmcontent__c
            , utmterm__c
            , reregisterutmsource__c
            , reregisterutmmedium__c
            , reregisterutmcampaign__c
            , reregisterutmcontent__c
            , reregisterutmterm__c
            , gclid__c
            , inflow_route__c
            , reregister_inflow_route__c                             -- 再登録流入経路
            , registration_route01__c
            , registration_route02__c
            , desired_industry__c
            , age_group__c
            , desired_occupation__c
            , experience_in_construction_management__c
            , field_supervisor_experience__c
            , registration_date__c_for_calculation
            , saitourokubi_adkeiyu__c_for_calculation
            , saitourokubigaibukeiyu__c_for_calculation
            , saitourokubiseokeiyu__c_for_calculation
            , saitourokubisyukeiyou__c_for_calculation
            , new_entry_flag                                        -- 新規フラグ
            , contact_date
            , contact_month1
            , branch
            , occupation
            , area
            , entrance_flag                                         -- 入口フラグ(接触数カウントから除外するために活用)
            , experience                                            -- 施工管理経験者
            , young_experience                                      -- 若年層経験者
            , construction_management_experience                    -- 施工管理経験者
            , construction_industry_experience                      -- 施工管理経験有無
            , age_group
            , work_style                                            -- 希望勤務形態
            , timing                                                -- 希望転職時期
            , const_desired_1                                       -- 施工管理における希望職種：建築施工管理
            , const_desired_2                                       -- 施工管理における希望職種：土木施工管理
            , const_desired_3                                       -- 施工管理における希望職種：電気施工管理
            , const_desired_4                                       -- 施工管理における希望職種：電気設備管理
            , const_desired_5                                       -- 施工管理における希望職種：施工図・設計
            , const_desired_6                                       -- 施工管理における希望職種：施工図作成
            , const_desired_7                                       -- 施工管理における希望職種：空調設備施工管理
            , const_desired_8                                       -- 施工管理における希望職種：CADオペレーター
            , const_desired_9                                       -- 施工管理における希望職種：設備施工管理
            , const_desired_10                                      -- 施工管理における希望職種：衛生設備施工管理
            , const_desired_11                                      -- 施工管理における希望職種：プラント施工管理
            , const_desired_12                                      -- 施工管理における希望職種：計装
            , const_desired_13                                      -- 施工管理における希望職種：その他
            , cutoff_date1                                          -- 〆日（昨日〆）修正
            , utmsource__c
            , utmmedium__c
            , rt_flg
            , mt_flg
            , entry_route
            , judge_entry_route
            , '通常' AS vaccine_flg
            , 1 AS nu_priority_flg                                  -- 営業⇒NU連携における経路優先付けのためのフラグ
        FROM crm_rereg_preprocessed
        ),

    normal_crmrereg_history AS (
        SELECT 
            cd__c
            , ARRAY_AGG(STRUCT(contact_date, nu_priority_flg) ORDER BY contact_date DESC, nu_priority_flg ASC) AS arr_history
        FROM normal_crmrereg_integrated
        WHERE cd__c IS NOT NULL
        GROUP BY cd__c
    ),

    nu_record AS ( -- NU対象のレコード
        SELECT *
        FROM `tryt-bigquery-pj.marketing_edit_v2.01_11_01_nu_rank`                  -- 接触月が25年7月以降のレコードはaccumulated由来のテーブルから引用する
        WHERE DATE_TRUNC(nusalescollaborationdate__pc, MONTH) >= DATE "2025-07-01"  
        UNION ALL
        SELECT * 
        FROM `tryt-bigquery-pj.marketing_edit_v2.01_11_01_nu_rank_past_20250630`    -- 接触月が25年6月以前のレコードは25年6月まで運用していた"snap_shot_master"というスナップショットから取得したテーブルから引用する 【重要】01_11_01_nu_rank で項目追加が発生した場合は、pastにおいても当該項目を追加すること
        WHERE DATE_TRUNC(nusalescollaborationdate__pc, MONTH) BETWEEN target_start_date AND DATE "2025-06-01"
        ),

    nu_preprocessed AS ( -- NU対象のレコードに対して、「通常KPI」/CRM再登録の項目を突合
        SELECT
            t1.* EXCEPT(contact_date , contact_month1 , entry_route , judge_entry_route)
            , ROW_NUMBER() OVER(PARTITION BY t1.cd__c , t1.followupchangedmonth__pc /*NU対象変更月*/ ORDER BY t2.contact_date DESC , t2.nu_priority_flg ASC) AS nu_flg
            , CURRENT_DATE('Asia/Tokyo') - 1 AS cutoff_date1        -- 〆日（昨日〆）修正
            , t1.nusalescollaborationdate__pc AS contact_date       -- 接触日 ★★★【NU】営業連携日が「接触日」として扱われる (以降のクエリ処理で、【NU】営業連携日 が、他経路における登録日と同義で扱われる)★★★
            , CASE 
                WHEN CURRENT_DATE('Asia/Tokyo') - 1 < t1.nusalescollaborationdate__pc THEN NULL 
                ELSE t1.nusalescollaborationmonth__pc 
            END AS contact_month1                                   -- 接触月 
            , 'NU' AS entry_route
            , CASE
                WHEN t1.nusalescollaborationdate__pc IS NULL THEN '営業連携なし'
                WHEN t1.nusalescollaborationdate__pc BETWEEN t1.followupchangeddate__c AND DATE_ADD(t1.followupchangeddate__c , INTERVAL 1 MONTH) - 1 THEN '1か月以内'
                WHEN t1.nusalescollaborationdate__pc BETWEEN DATE_ADD(t1.followupchangeddate__c , INTERVAL 1 MONTH) AND DATE_ADD(t1.followupchangeddate__c , INTERVAL 3 MONTH) - 1 THEN '3か月以内'
                WHEN t1.nusalescollaborationdate__pc BETWEEN DATE_ADD(t1.followupchangeddate__c , INTERVAL 3 MONTH) AND DATE_ADD(t1.followupchangeddate__c , INTERVAL 6 MONTH) - 1 THEN '6か月以内'
                WHEN t1.nusalescollaborationdate__pc BETWEEN DATE_ADD(t1.followupchangeddate__c , INTERVAL 6 MONTH) AND DATE_ADD(t1.followupchangeddate__c , INTERVAL 12 MONTH) - 1 THEN '1年以内'
                WHEN t1.nusalescollaborationdate__pc BETWEEN DATE_ADD(t1.followupchangeddate__c , INTERVAL 12 MONTH) AND DATE_ADD(t1.followupchangeddate__c , INTERVAL 24 MONTH) - 1 THEN '2年以内'
                ELSE '2年以上' 
            END AS judge_entry_route                                -- 他経路に倣う形でNUについても意図的に作成されたと思われる(250512 KI追記) 
        FROM nu_record AS t1
        LEFT JOIN normal_crmrereg_history AS t_hist
            ON t1.cd__c = t_hist.cd__c
        LEFT JOIN UNNEST(ARRAY(
            SELECT AS STRUCT
                h.contact_date
                , h.nu_priority_flg
            FROM UNNEST(t_hist.arr_history) AS h
            WHERE t1.followupchangeddate__c >= h.contact_date
            ORDER BY
                h.contact_date DESC
                , h.nu_priority_flg ASC
            LIMIT 1
        )) AS t2
    ),

    normal_crmrereg_nu_integrated AS ( -- 【「通常KPI」+ CRM再登録】のレコードと【NU対象】のレコードのユニオン
        SELECT
            * EXCEPT(nu_priority_flg)
            , CAST(NULL AS DATE) AS followupchangedmonth__pc
            , CAST(NULL AS DATE) AS followupchangeddate__c
            , CAST(NULL AS DATE) AS numutemonth__pc
            , CAST(NULL AS DATE) AS numuteday__pc
        FROM normal_crmrereg_integrated 
        UNION ALL
        SELECT
            jsid
            , cd__c
            , saitourokubigaibukeiyu__c
            , registration_route_fisrst_navi_kaigo__c
            , registration_route_kyuzinzyanal__c
            , registration_route_nursing__c
            , registration_routekaigolila__c
            , registration_route_care_job_navi__c
            , registration_route_fisrst_navi__c
            , registrationroutenurse_e__c
            , registration_route_nurse__c
            , registration_routenasusenka__c
            , registration_route_childcare_job_navi__c
            , registration_routelisujobs__c
            , registration_route_medridgechildcares__c
            , registration_route_nikkei_medicals__c
            , nurseryteachermikata__c
            , registration_route_hoikunooshigoto__c
            , registration_route_eiyoshinooshigoto__c
            , registration_route_friend__c
            , registration_routeyakukyari__c                         -- ※20250116追加
            , age__c
            , yuusensikakusyuukeiyou__c
            , kiboukinmukeitaisyuukei__c
            , employment_type_shift_pattern1__c
            , affiliate_approval_key__c
            , utmsource_first__c
            , reregistre_web_requirements__c
            , reregistre_web_changehopetime__c
            , web_job_application_number__c
            , job_change_time_from__c
            , registration_route_owned_media__c
            , registration_route_external_site__c                   -- ※20241111追加
            , registration_date__c
            , saitourokubi_adkeiyu__c
            , saitourokubiseokeiyu__c
            , saitourokubisyukeiyou__c
            , dummy_step1_from_js                                   -- 求職者OBJから取得したfirst_hearing__c 
            , dummy_step2_from_js                                   -- 求職者OBJから取得したjob_suggestion__c
            , dummy_step3_from_js                                   -- 求職者OBJから取得したdetermination_of_interview_date__c
            , dummy_step4_from_js                                   -- 求職者OBJから取得したinterview_implementation__c
            , dummy_step5_from_js                                   -- 求職者OBJから取得したagreement__c
            , billing_state
            , branch_text__c
            , department_in_charge__c
            , name
            , owner_id
            , status__c
            , referral_status__c
            , deletion_hope_reason__c
            , web_changehopetime__c
            , utmsource__c_not_first
            , utmmedium__c_not_first
            , utmcampaign__c
            , utmcontent__c
            , utmterm__c
            , reregisterutmsource__c
            , reregisterutmmedium__c
            , reregisterutmcampaign__c
            , reregisterutmcontent__c
            , reregisterutmterm__c
            , gclid__c
            , inflow_route__c
            , reregister_inflow_route__c                            -- 再登録流入経路
            , registration_route01__c
            , registration_route02__c
            , desired_industry__c
            , age_group__c
            , desired_occupation__c
            , experience_in_construction_management__c
            , field_supervisor_experience__c
            , registration_date__c_for_calculation
            , saitourokubi_adkeiyu__c_for_calculation
            , saitourokubigaibukeiyu__c_for_calculation
            , saitourokubiseokeiyu__c_for_calculation
            , saitourokubisyukeiyou__c_for_calculation
            , new_entry_flag                                        -- 新規フラグ
            , contact_date
            , contact_month1
            , branch
            , occupation
            , area
            , entrance_flag                                         -- 入口フラグ(接触数カウントから除外するために活用)
            , experience                                            -- 施工管理経験者
            , young_experience                                      -- 若年層経験者
            , construction_management_experience                    -- 施工管理経験者
            , construction_industry_experience                      -- 施工管理経験有無
            , age_group
            , work_style                                            -- 希望勤務形態
            , timing                                                -- 希望転職時期
            , const_desired_1                                       -- 施工管理における希望職種：建築施工管理
            , const_desired_2                                       -- 施工管理における希望職種：土木施工管理
            , const_desired_3                                       -- 施工管理における希望職種：電気施工管理
            , const_desired_4                                       -- 施工管理における希望職種：電気設備管理
            , const_desired_5                                       -- 施工管理における希望職種：施工図・設計
            , const_desired_6                                       -- 施工管理における希望職種：施工図作成
            , const_desired_7                                       -- 施工管理における希望職種：空調設備施工管理
            , const_desired_8                                       -- 施工管理における希望職種：CADオペレーター
            , const_desired_9                                       -- 施工管理における希望職種：設備施工管理
            , const_desired_10                                      -- 施工管理における希望職種：衛生設備施工管理
            , const_desired_11                                      -- 施工管理における希望職種：プラント施工管理
            , const_desired_12                                      -- 施工管理における希望職種：計装
            , const_desired_13                                      -- 施工管理における希望職種：その他
            , cutoff_date1                                          -- 〆日（昨日〆）修正
            , utmsource__c
            , utmmedium__c
            , rt_flg
            , mt_flg
            , entry_route
            , judge_entry_route
            , '通常' AS vaccine_flg
            , followupchangedmonth__pc
            , followupchangeddate__c
            , numutemonth__pc
            , numuteday__pc
        FROM nu_preprocessed
        WHERE nu_flg = 1 -- (PARTITION BY t1.cd__c , t1.followupchangedmonth__pc /*NU対象変更月*/ ORDER BY t2.contact_date DESC , t2.nu_priority_flg ASC)により生成
        ),

    medium_integrated AS ( -- 広告経由と判定されたレコードにおいて、媒体情報を突合する 【注意】SF側の項目変更等により随時改修が発生する
        SELECT
            t1.*
            , CASE 
                WHEN t1.entry_route = '広告' AND 
                    (
                        ( t1.contact_date = t1.registration_date__c AND t1.utmsource_first__c IS NULL) 
                        OR 
                        t1.contact_date = t1.saitourokubigaibukeiyu__c_for_calculation
                    ) THEN 
                    CASE 
                        WHEN t1.registration_route_fisrst_navi_kaigo__c IS NOT NULL AND t1.registration_route_fisrst_navi_kaigo__c <> 0 THEN 'ファーストナビ'
                        WHEN t1.registration_route_kyuzinzyanal__c IS NOT NULL AND t1.registration_route_kyuzinzyanal__c <> 0 THEN '求人ジャーナル'
                        WHEN (t1.registration_route_care_job_navi__c IS NOT NULL AND t1.registration_route_care_job_navi__c <> 0) 
                            OR (t1.registration_route_owned_media__c LIKE '%ケア求人ナビ%')
                            OR (t1.registration_route_owned_media__c LIKE '%看護師・ナース求人ナビ%') THEN '求人ナビ'
                        WHEN t1.registration_route_fisrst_navi__c IS NOT NULL AND t1.registration_route_fisrst_navi__c <> 0 THEN 'ファーストナビ'
                        WHEN t1.registrationroutenurse_e__c IS NOT NULL AND t1.registrationroutenurse_e__c <> 0 THEN 'ナースエージェント'
                        WHEN t1.registration_route_nurse__c IS NOT NULL AND t1.registration_route_nurse__c <> 0 THEN 'ナースワーカー'
                        WHEN t1.registration_routenasusenka__c IS NOT NULL AND t1.registration_routenasusenka__c <> 0 THEN 'ナース専科'
                        WHEN t1.registration_route_nikkei_medicals__c IS NOT NULL AND t1.registration_route_nikkei_medicals__c <> 'false' THEN '日経'
                        WHEN t1.registration_route_medridgechildcares__c IS NOT NULL AND t1.registration_route_medridgechildcares__c <> 'false' THEN 'メドリッジ'
                        WHEN (t1.registration_route_childcare_job_navi__c IS NOT NULL AND t1.registration_route_childcare_job_navi__c <> 0) 
                            OR (t1.registration_route_owned_media__c LIKE '%保育士求人ナビ%') THEN '求人ナビ'
                        WHEN t1.registration_routelisujobs__c IS NOT NULL AND t1.registration_routelisujobs__c <> 'false' THEN 'リスジョブ'
                        WHEN t1.nurseryteachermikata__c IS NOT NULL AND t1.nurseryteachermikata__c <> 'false' THEN '保育士のミカタ'
                        WHEN t1.registration_route_owned_media__c LIKE '%POS求人ナビ%' THEN '求人ナビ'
                        WHEN t1.registration_route_owned_media__c LIKE '%ケアキャリアナビ%' THEN '求人ナビ'
                        WHEN t1.registration_route_external_site__c LIKE '%保育isお仕事%' THEN '保育isお仕事'   -- ※20241111追加
                        WHEN t1.registration_route_friend__c IS NOT NULL AND t1.registration_route_friend__c <> 0 THEN '友人紹介'
                        WHEN t1.registration_routeyakukyari__c IS NOT NULL AND t1.registration_routeyakukyari__c <> 0  THEN '薬キャリ' -- ※20250116追加
                        WHEN t2.medium_category_1 IS NULL THEN 'その他'
                        WHEN t2.medium_category_1 = "AF（SEP1）" AND t1.occupation = '介護職' AND contact_month1 >= DATE "2024-10-01" THEN "AF（NM）" ---- 20250129追加
                        ELSE t2.medium_category_1 
                    END
                WHEN t1.entry_route = '広告' THEN 
                    CASE 
                        WHEN t2.medium_category_1 IS NULL THEN '不明' 
                        WHEN t2.medium_category_1 = "AF（SEP1）" AND t1.occupation = '介護職' AND contact_month1 >= DATE "2024-10-01" THEN "AF（NM）" ---- 20250129追加
                        ELSE t2.medium_category_1 
                    END
                ELSE '広告以外' 
            END AS medium -- 媒体 ★★★媒体が変更された際は、01_02_entrance_editだけでなく本クエリも改修すること
        FROM normal_crmrereg_nu_integrated AS t1
        LEFT JOIN `tryt-bigquery-pj.production_tryt.master_medium` AS t2    -- 媒体用マスタ https://docs.google.com/spreadsheets/d/1tVy_iOad8mgyKCzG3XVbcKyyphGx0dosTHpRBb9DR80/edit?pli=1&gid=1134938641#gid=1134938641
            ON CONCAT(CASE WHEN t1.utmsource__c IS NULL THEN '' ELSE LOWER(t1.utmsource__c) END , CASE WHEN t1.utmmedium__c IS NULL THEN '' ELSE LOWER(t1.utmmedium__c) END) = 
                CONCAT(CASE WHEN t2.utm_source IS NULL THEN '' ELSE LOWER(t2.utm_source) END , CASE WHEN t2.utm_medium IS NULL THEN '' ELSE LOWER(t2.utm_medium) END) 
            /*
            ★★★★★★★★★★重要★★★★★★★★★★
            広告経由の場合、媒体マスタにおけるutmsource__cとutmmedium__cの組み合わせにより基本的に媒体名が決定される
            →媒体名に紐づく実績値に異常がある場合は、utmsource__c/utmmedium__c (marketing_edit_v2.01_04_02_record_preprocessedにおける下記が出所) および媒体用マスタを検証すること

                , CASE 
                    WHEN t1.occupation <> '施工管理' AND t1.judge_entry_route LIKE '%新規%' THEN t2.utmsource_first__c  -- 紹介事業で新規登録の場合は、career_account_job_seeker.utmsource_first__c
                    ELSE t1.utmsource__c_not_first -- それ以外の場合は、career_account_job_seeker.utmsource__c
                END AS utmsource__c
                , CASE 
                    WHEN t1.occupation <> '施工管理' AND t1.judge_entry_route LIKE '%新規%' THEN t2.utmmedium_first__c  -- 紹介事業で新規登録の場合は、career_account_job_seeker.utmmedium_first__c
                    ELSE t1.utmmedium__c_not_first -- それ以外の場合は、career_account_job_seeker.utmmedium__c
                END AS utmmedium__c

            ※ 広告経由について、UTM情報の欠損による経路毎実績の異常が発生した場合(頻発する)は、求職者OBJのバックアップテーブル等を調査し、開発課等に連絡する
            */
      ),

    entrance_info AS ( -- 都道府県/資格情報の突合
        SELECT
            t1.*
            , t2.prefecture_name
            , t3.qualification_flag  -- 資格フラグ
            , CASE 
                WHEN t3.qualification_flag IS NULL THEN '資格なし' 
                WHEN t3.qualification_flag = 1 THEN '資格あり' 
                ELSE '資格なし' 
            END AS qualification    -- 資格有無
            , CONCAT(CONCAT(t1.cd__c , t1.contact_date) , t1.judge_entry_route) AS flg -- ★★★★★★後続のクエリでリレーションに使用する★★★★★★
        FROM medium_integrated AS t1
        LEFT JOIN `tryt-bigquery-pj.production_tryt.master_prefecture` AS t2    -- 都道府県マスタ https://docs.google.com/spreadsheets/d/1tVy_iOad8mgyKCzG3XVbcKyyphGx0dosTHpRBb9DR80/edit?gid=1786170425#gid=1786170425
            ON t1.billing_state = t2.prefecture_flag                            -- 都道府県整形
        LEFT JOIN `tryt-bigquery-pj.production_tryt.master_qualification` AS t3 -- 資格マスタ https://docs.google.com/spreadsheets/d/1tVy_iOad8mgyKCzG3XVbcKyyphGx0dosTHpRBb9DR80/edit?gid=1092030824#gid=1092030824
            ON t1.occupation = t3.occupation
                AND t1.yuusensikakusyuukeiyou__c = t3.priority_qualification    -- 職種別に有効資格者を結び付け
      )

--最終集計
SELECT
    *
FROM entrance_info;
-- marketing_edit_v2.01_05_01_record_raw



-- marketing_edit_v2.02_01_career_const_action_aggregated
    -- 更新日：2026/07/17
    -- 作業者：細江
    -- 更新内容：タイムアウト（DEADLINE_EXCEEDED）エラーに伴うリファクタリング

/*
■実行内容
career_task/const_taskのテーブルにおいてKPI集計に必要な各ステップ項目を抽出しユニオンする
紹介事業あるいは施工管理の各アクションの集計定義に変更があった場合は本テーブルを改修する
(PK：id_task)
*/

CREATE OR REPLACE TABLE `tryt-bigquery-pj.marketing_edit_v2.02_01_career_const_action_aggregated` PARTITION BY created_date CLUSTER BY cd__c AS 
WITH 
    career_raw AS ( -- careerコンタクト履歴raw
        SELECT
            t1.* EXCEPT(created_date)
            , CASE WHEN t1.activity_date < t1.created_date THEN t1.activity_date ELSE CAST(t1.last_modified_date AS DATE) END AS created_date -- activity_dateが過去であればactivity_date、未来であればlast_modified_date
            , t1.sales_pic_area__c AS branch                                           -- 担当拠点
            , t5.sales_office
            , t4.occupation
            , t2.name AS sales_name
            , t3.cd__c                                                                 
            , t3.birthday__c AS birthday
        FROM `tryt-bigquery-pj.marketing_edit_v2.02_00_career_task_temp_field` AS t1
        LEFT JOIN `tryt-bigquery-pj.production_tryt_informatica.career_user` AS t2
            ON t1.owner_id = t2.id                                                     -- 求職者とユーザの紐づけ
        INNER JOIN `tryt-bigquery-pj.marketing_edit_v2.01_00_career_account_job_seeker_temp_field` AS t3
            ON t1.job_seeker_id__c = LEFT(t3.id,15)                                    -- 求職者とコンタクト履歴の紐づけ
        LEFT JOIN `tryt-bigquery-pj.production_tryt.master_branch` AS t4               -- 支社マスタ https://docs.google.com/spreadsheets/d/1tVy_iOad8mgyKCzG3XVbcKyyphGx0dosTHpRBb9DR80/edit?gid=1094227535#gid=1094227535
            ON t1.sales_pic_area__c = t4.branch
        LEFT JOIN `tryt-bigquery-pj.production_tryt.master_sales_office` AS t5         -- 営業所マスタ https://docs.google.com/spreadsheets/d/1se4E_tSOTM50Td9WsTmpYhpLd3_CIYQMjYT36uupTVc/edit?gid=1620852360#gid=1620852360
            ON t1.department_in_charge__c = t5.branch_flag
        WHERE t1.created_date >= DATE_SUB(DATE_TRUNC(CURRENT_DATE('Asia/Tokyo'), MONTH), INTERVAL 60 MONTH)   -- レコード数が長大であるためリソースの観点から5ヵ年に限定
        ),

    const_raw AS ( -- constコンタクト履歴raw
        SELECT
            t1.* EXCEPT(created_date , scheduled_assignment_date__c)
            , CASE WHEN t1.activity_date < t1.created_date THEN t1.activity_date ELSE CAST(t1.last_modified_date AS DATE) END AS created_date -- activity_dateが過去であればactivity_date、未来であればlast_modified_date
            , t2.roll_name__c AS branch                                                -- 担当拠点
            , t6.sales_office
            , t5.occupation
            , t2.name AS sales_name
            , t2.roll_name__c
            , t4.cd__c    
            , t4.birthdate__c AS birthday
            , t4.neg_stat_date16__c
            , t4.hiredate__c
            , t4.scheduled_assignment_date__c
        FROM `tryt-bigquery-pj.marketing_edit_v2.02_00_const_task_temp_field` AS t1
        LEFT JOIN `tryt-bigquery-pj.production_tryt_informatica.const_user` AS t2
            ON t1.owner_id = t2.id  -- 求職者とユーザの紐づけ
        INNER JOIN `tryt-bigquery-pj.production_tryt_informatica.const_contact` AS t3
            ON t1.job_seeker__c = t3.id    
        INNER JOIN `tryt-bigquery-pj.marketing_edit_v2.01_00_const_account_job_seeker_temp_field` AS t4
            ON t3.account_id = t4.id -- 企業担当者とコンタクト履歴の結び付け
        LEFT JOIN `tryt-bigquery-pj.production_tryt.master_branch` AS t5               -- 支社マスタ https://docs.google.com/spreadsheets/d/1tVy_iOad8mgyKCzG3XVbcKyyphGx0dosTHpRBb9DR80/edit?gid=1094227535#gid=1094227535
            ON t2.roll_name__c = t5.branch
        LEFT JOIN `tryt-bigquery-pj.production_tryt.master_sales_office` AS t6         -- 営業所マスタ https://docs.google.com/spreadsheets/d/1se4E_tSOTM50Td9WsTmpYhpLd3_CIYQMjYT36uupTVc/edit?gid=1620852360#gid=1620852360
            ON t1.department_in_charge__c = t6.branch_flag
        ),

    career_contact AS ( -- careerコンタクト履歴ステップ0.5-5に関するレコード
        SELECT
            id AS id_task
            , cd__c                     -- SFID
            , occupation
            , sales_office
            , birthday
            , created_date              -- 作成日
            , sales_name                -- 営業担当
            , owner_id                  -- 営業担当id
            , branch                    -- 担当拠点
            , department_in_charge__c   -- 担当部署
            , CASE 
                WHEN result__c IN('成功' , '失敗') THEN 'step0.5'   
                ELSE NULL
            END AS action_category0_5   -- 通電 (ヒアリング等を含むCASE式で纏めようとすると、「成功」/「失敗」は殆どのアクションをカバーしてしまい常にそれが選択されるため、別項目で設定する 250217 KI追記)
            , CASE
                WHEN action__c IN('ファーストヒアリング' , '掘り起こし') AND result__c = '成功' THEN 'step1'  -- ヒアリング
                WHEN 
                    (job_offer_action__c LIKE '%求人提案%' AND result__c IN('成功' , '失敗')) 
                    OR 
                    (branch LIKE '%派遣%' AND (dispatch__c = '求人提案（単一）' OR dispatch__c = '求人提案（複数）') AND result__c = '成功') 
                    THEN 'step2'        -- 求人提案
                WHEN 
                    (interview__c = '面接日決定' AND result__c = '成功') 
                    OR 
                    (branch LIKE '%派遣%' AND dispatch__c = '業確設定' AND result__c = '成功') 
                    THEN 'step3'        -- 面接日決定/業確設定
                WHEN 
                    (interview__c = '面接実施' AND result__c = '成功')
                    OR 
                    (branch LIKE '%派遣%' AND dispatch__c = '業確実施' AND result__c = '成功') 
                    THEN 'step4'        -- 面接実施/業確実施
                WHEN 
                    (close__c = '内定連絡' AND result__c = '成功')
                    OR 
                    (branch LIKE '%派遣%' AND dispatch__c = '業確結果受領' AND result__c = '成功') 
                    THEN 'step5'        -- 内定連絡/業確結果受領
                WHEN 
                    (nu_action__c = '【NU】ファーストヒアリング' AND result__c LIKE '%成功%') 
                    THEN 'NUstep1'      -- NUヒアリング成功
                WHEN nu_action__c = '【NU】ファーストヒアリング' 
                    THEN 'NUstep0'      -- NUヒアリング全体
                ELSE NULL 
            END AS action_category
            , contact_means__c          -- 手段
            , result__c                 -- 結果
            , CASE 
                WHEN 
                    (
                        branch LIKE '%派遣%' 
                        AND (dispatch__c = '求人提案（単一）' OR dispatch__c = '求人提案（複数）')
                        AND result__c = '成功'
                    )                   -- 求人提案
                    OR (branch LIKE '%派遣%' AND dispatch__c = '業確設定' AND result__c = '成功')      -- 業確設定
                    OR (branch LIKE '%派遣%' AND dispatch__c = '業確実施' AND result__c = '成功')      -- 業確実施
                    OR (branch LIKE '%派遣%' AND dispatch__c = '業確結果受領' AND result__c = '成功')   -- 業確結果受領
                        THEN '派遣'
                ELSE '紹介' 
            END AS type                 -- 突合にあたり紹介と派遣で分ける必要があるので、フラグを作成
        FROM career_raw
        WHERE created_date >= target_start_date
            AND (
                    result__c IN('成功' , '失敗')                                                      -- 通電
                    OR (action__c IN('ファーストヒアリング' , '掘り起こし') AND result__c = '成功')        -- ヒアリング
                    OR (job_offer_action__c LIKE '%求人提案%' AND result__c IN('成功' , '失敗'))        -- 求人提案
                    OR (interview__c = '面接日決定' AND result__c = '成功')                             -- 面接日決定
                    OR (interview__c = '面接実施' AND result__c = '成功')                               -- 面接実施
                    OR (close__c = '内定連絡' AND result__c = '成功')                                   -- 内定連絡
                    OR (nu_action__c = '【NU】ファーストヒアリング' AND result__c LIKE '%成功%')          -- NUヒアリング成功
                    OR (nu_action__c = '【NU】ファーストヒアリング')                                     -- NUヒアリング全体
                    OR (etc__c LIKE '%カレッジ提案%' AND result__c = '成功')                            -- カレッジ提案
                    OR (branch LIKE '%派遣%' AND (dispatch__c = '求人提案（単一）' OR dispatch__c = '求人提案（複数）') AND result__c = '成功') -- 求人提案
                    OR (branch LIKE '%派遣%' AND dispatch__c = '業確設定' AND result__c = '成功')       -- 業確設定
                    OR (branch LIKE '%派遣%' AND dispatch__c = '業確実施' AND result__c = '成功')       -- 業確実施
                    OR (branch LIKE '%派遣%' AND dispatch__c = '業確結果受領' AND result__c = '成功')    -- 業確結果受領
                )
        ),

    const_contact AS ( -- constコンタクト履歴ステップ0.5-5に関するレコード
        SELECT
            id AS id_task
            , cd__c                     -- SFID
            , occupation
            , sales_office
            , birthday
            , created_date              -- 作成日
            , sales_name                -- 営業担当
            , owner_id                  -- 営業担当id
            , branch                    -- 担当拠点
            , branch AS department_in_charge__c -- 担当部署
            , CASE 
                WHEN result__c IN('成功' , '失敗（接触あり）') THEN 'step0.5'
                ELSE NULL 
            END AS action_category0_5   -- 通電 (ヒアリング等を含むCASE式で纏めようとすると、「成功」/「失敗」は殆どのアクションをカバーしてしまい常にそれが選択されるため、別項目で設定する 250217 KI追記)
            , CASE 
                WHEN (action__c IN('ヒアリング' , '掘り起こし') AND result__c IN('成功' , '失敗（接触あり）')) THEN 'step1'  -- ヒアリング
                WHEN (sub_action_or_result1__c = '面接日決定' AND result__c = '成功')
                    OR (referral_action__c = '求人提案' AND result__c = '成功') THEN 'step2'                            -- 面接日決定/求人提案
                WHEN (sub_action_or_result1__c = '売込み' AND (status__c IS NULL OR status__c <> '配属')) 
                    OR (referral_action__c = '面接日決定' AND result__c = '成功') THEN 'step3'                          -- 売込み/面接日決定
                WHEN (sub_action_or_result1__c = '業確日決定' AND (result__c IS NULL OR result__c NOT LIKE '%失敗%')) 
                    OR (referral_action__c = '面接実施' AND result__c = '成功') THEN 'step4'                            -- 業確日決定/面接実施
                WHEN 
                    (
                        created_date < DATE('2022-04-01') 
                        AND sub_action_or_result1__c = '業確結果受領' 
                        AND result__c = '成功' 
                        AND (status__c IS NULL OR status__c <> '配属') 
                        AND (employmenttype__c IS NULL OR (employmenttype__c <> '紹介' AND employmenttype__c <> '紹介（確定）'))
                    )
                    OR 
                    (
                        created_date >= DATE('2022-04-01') 
                        AND 
                        (
                            sub_action_or_result1__c = '配属日決定' 
                            AND (neg_stat_date16__c IS NULL OR neg_stat_date16__c >= created_date OR hiredate__c = scheduled_assignment_date__c) 
                            AND (employmenttype__c IS NULL OR (employmenttype__c <> '紹介' AND employmenttype__c NOT LIKE '%紹介（%')) 
                            AND status__c = '交渉中'
                        )
                    ) 
                    OR (referral_action__c = '内定連絡' AND result__c = '成功') 
                        THEN 'step5'    -- 配属日決定/内定連絡
                ELSE NULL 
            END AS action_category
            , contact_means__c          -- 手段
            , result__c                 -- 結果
            , CASE 
                WHEN (referral_action__c = '求人提案' AND result__c = '成功')               -- 求人提案
                   OR (referral_action__c = '面接日決定' AND result__c = '成功')            -- 面接日決定
                   OR (referral_action__c = '面接実施' AND result__c = '成功')              -- 面接実施
                   OR (referral_action__c = '内定連絡' AND result__c = '成功') THEN '紹介'  -- 内定連絡
                ELSE '派遣' 
            END AS type                -- 突合にあたり紹介と派遣で分ける必要があるので、フラグを作成
        FROM const_raw
        WHERE created_date >= target_start_date
            AND (
                    result__c IN('成功' , '失敗（接触あり）')  -- 通電
                    OR 
                    (action__c IN('ヒアリング' , '掘り起こし') AND result__c IN('成功' , '失敗（接触あり）'))            -- ヒアリング 
                    OR 
                    (sub_action_or_result1__c = '面接日決定' AND result__c = '成功')                                 -- 面接日決定
                    OR 
                    (sub_action_or_result1__c = '売込み' AND (status__c IS NULL OR status__c <> '配属'))            -- 売込み
                    OR
                    (sub_action_or_result1__c = '業確日決定' AND (result__c IS NULL OR result__c NOT LIKE '%失敗%')) -- 業確日決定
                    OR 
                    (
                        created_date < DATE('2022-04-01') 
                        AND sub_action_or_result1__c = '業確結果受領' 
                        AND result__c = '成功' 
                        AND (status__c IS NULL OR status__c <> '配属') 
                        AND (employmenttype__c IS NULL OR (employmenttype__c <> '紹介' AND employmenttype__c <> '紹介（確定）'))
                    )                   -- 配属日決定
                    OR 
                    (
                        created_date >= DATE('2022-04-01')
                        AND 
                        (
                            sub_action_or_result1__c = '配属日決定'
                            AND (neg_stat_date16__c IS NULL OR neg_stat_date16__c >= created_date OR hiredate__c = scheduled_assignment_date__c) 
                            AND (employmenttype__c IS NULL OR (employmenttype__c <> '紹介' AND employmenttype__c NOT LIKE '%紹介（%'))
                            AND status__c = '交渉中'
                        )
                    )                   -- 配属日決定
                    OR (referral_action__c = '求人提案' AND result__c = '成功')     -- 求人提案
                    OR (referral_action__c = '面接日決定' AND result__c = '成功')   -- 面接日決定
                    OR (referral_action__c = '面接実施' AND result__c = '成功')     -- 面接実施
                    OR (referral_action__c = '内定連絡' AND result__c = '成功')     -- 内定連絡
                ) 
        ),

    contact_integrated AS ( -- career/constコンタクト履歴をユニオン
        SELECT * FROM career_contact 
        UNION ALL
        SELECT * FROM const_contact
        )

--最終集計
SELECT
    *
FROM contact_integrated;
-- marketing_edit_v2.02_01_career_const_action_aggregated



-- marketing_edit_v2.03_01_career_contract_raw
    -- 更新日：2026/07/17
    -- 作業者：細江
    -- 更新内容：タイムアウト（DEADLINE_EXCEEDED）エラーに伴うリファクタリング

/*
■実行内容
紹介事業の売上請求管理集計定義に則り、レコードを引用
また、同内容に関する契約変更や辞退退職に関する情報を整理
(PK：id_invoice)
*/

CREATE OR REPLACE TABLE `tryt-bigquery-pj.marketing_edit_v2.03_01_career_contract_raw` AS 
WITH 
    account_sales AS ( -- 売上請求管理のレコードを抽出
        SELECT
            id AS id_invoice
            , created_date
            , CAST(sales_amount__c AS int64) AS sales_amount__c
            , record_type_id
            , IFNULL(same_target_original__c, name) AS invoice_name 
            , worker_sfid__c AS cd__c
            , industry__c
            , branch_name__c AS branch_text__c
            , department_in_charge__c
            , accounting_receipt_date__c -- 営業承認日
            , DATE(documents_check_date__c) AS record_date
            , DATE_TRUNC(documents_check_date__c , MONTH) AS record_month_before_edit --計上書類チェック月
            , IFNULL(final_expected_date_of_employment_after__c, expected_date_of_employment__c) AS expected_date_of_employment__c -- 入職予定日
            , sales_name__c
            , sales_name_report__c AS owner_name
            , facility_name__c
            , cancellation_type__c
            , request_type2__c
            , form2__c
            , documents_check__c
            , recording_type__c
            , accrual_date__c
            , refund__c
            , age2__c AS age__c
            , auth_result_date__c
            , ROW_NUMBER() OVER(PARTITION BY IFNULL(same_target_original__c, name) ORDER BY documents_check_date__c ASC) AS record_rank -- 初回の売上のレコードを抽出用(同一の対象案件番号(same_target_original__c)に対して、初回の計上書類チェック日で並び替える)
        FROM `tryt-bigquery-pj.marketing_edit_v2.03_00_career_invoice_temp_field`
        WHERE approval_status__c LIKE '%承認%' 
            AND (invalidapplication2__c IS NULL OR invalidapplication2__c = 0)
            AND (request_type__c <> '違約金会計売上(直接交渉)' OR request_type__c IS NULL)
            AND 
                (
                    (request_type2__c <> '入職日変更' AND request_type2__c <> '支払日変更' AND request_type2__c <> 'マイナス相殺') 
                    OR 
                    request_type2__c IS NULL
                )
            AND DATE(documents_check_date__c) >= target_start_date
            AND documents_check__c = 1
            AND external_id__c IS NULL -- 統合時の外部重複を除外
    ),

    contract_amount AS ( -- グロス売上/純契約売上/成約数に関する集計用にフラグを作成
        SELECT
            *
            , CASE 
                WHEN record_type_id = '0120o000001JakyAAC' /*【12】キャス*/ OR record_type_id = '0120o000001juLFAAY' /*【10】入職日変更・支払日変更・売上訂正・返金・入職辞退*/ THEN 0 
                ELSE 1 
            END AS contract_count -- 成約数
            , CASE 
                WHEN 
                    (
                        ( cancellation_type__c <> '入職辞退' AND cancellation_type__c <> '入職後早期退職') 
                        OR 
                        cancellation_type__c IS NULL
                    ) 
                    AND (recording_type__c = '新規売上' OR recording_type__c = '売上訂正' OR recording_type__c = '入職後早期退職') 
                THEN 1 
                ELSE 0 
            END AS gross_flg -- グロス売上集計用フラグ
        FROM account_sales
        WHERE 
            (
                (record_type_id <> '0120o000001jylUAAQ' /*【11】情報変更／無効化申請*/ AND record_type_id <> '0120o000001juLGAAY' /*売上ヨミ*/) 
                OR 
                record_type_id IS NULL
            )
    ),

    retire_edit AS ( -- 辞退退職に関する情報を整理
        SELECT
            invoice_name
            , accrual_date__c
            , request_type2__c AS re_type
            , IFNULL(accrual_date__c, LEAST(record_date , expected_date_of_employment__c - 1)) AS retire_date               -- 辞退/退職日
            , sales_amount__c                                                                                               -- グロス売上
            , SUM(sales_amount__c) OVER(PARTITION BY invoice_name) AS retire_amount                                         -- 辞退/退職に伴う返金額
            , ROW_NUMBER() OVER(PARTITION BY invoice_name ORDER BY IFNULL(accrual_date__c, record_date) DESC) AS retire_flg -- 辞退/退職フラグ
        FROM contract_amount
        WHERE cancellation_type__c = '入職辞退' OR cancellation_type__c = '入職後早期退職'                                      -- 辞退/退職に関するレコードのみ抽出する
    ),

    retire_integrated AS ( -- 辞退退職に関する情報を突合
        SELECT
            t1.*
            , t2.retire_flg -- 辞退/退職フラグ
            , t2.retire_date -- 辞退/退職日
            , CASE 
                WHEN t2.retire_date < t1.expected_date_of_employment__c THEN '入職前辞退' 
                WHEN t2.retire_date >= t1.expected_date_of_employment__c THEN '入職後退職' 
                ELSE NULL 
            END AS retire_category -- 辞退退職情報
            , CASE 
                WHEN t2.retire_date IS NULL THEN NULL
                WHEN t2.retire_date < t1.expected_date_of_employment__c THEN - 1 -- 入職前
                WHEN t2.retire_date BETWEEN t1.expected_date_of_employment__c AND DATE_ADD(t1.expected_date_of_employment__c , INTERVAL 1 MONTH) - 1 THEN 0 -- 1カ月以内
                WHEN t2.retire_date BETWEEN DATE_ADD(t1.expected_date_of_employment__c , INTERVAL 1 MONTH) AND DATE_ADD(t1.expected_date_of_employment__c , INTERVAL 2 MONTH) - 1 THEN 1 -- 2カ月以内
                WHEN t2.retire_date BETWEEN DATE_ADD(t1.expected_date_of_employment__c , INTERVAL 2 MONTH) AND DATE_ADD(t1.expected_date_of_employment__c , INTERVAL 3 MONTH) - 1 THEN 2 -- 3カ月以内
                WHEN t2.retire_date BETWEEN DATE_ADD(t1.expected_date_of_employment__c , INTERVAL 3 MONTH) AND DATE_ADD(t1.expected_date_of_employment__c , INTERVAL 4 MONTH) - 1 THEN 3 -- 4カ月以内
                WHEN t2.retire_date BETWEEN DATE_ADD(t1.expected_date_of_employment__c , INTERVAL 4 MONTH) AND DATE_ADD(t1.expected_date_of_employment__c , INTERVAL 5 MONTH) - 1 THEN 4 -- 5カ月以内
                WHEN t2.retire_date BETWEEN DATE_ADD(t1.expected_date_of_employment__c , INTERVAL 5 MONTH) AND DATE_ADD(t1.expected_date_of_employment__c , INTERVAL 6 MONTH) - 1 THEN 5 -- 6カ月以内
                ELSE NULL 
            END AS retire_leadtime  -- 入職予定日に対する辞退退職までのリードタイム
            , t2.retire_amount      -- 辞退/退職に伴う返金額
        FROM contract_amount AS t1
        LEFT JOIN retire_edit AS t2
            ON t1.invoice_name = t2.invoice_name
                AND t1.contract_count = 1
                AND t2.retire_flg = 1 -- (PARTITION BY invoice_name ORDER BY IFNULL(accrual_date__c, record_date) DESC) により生成されている
    )

--最終集計
SELECT 
    *
FROM retire_integrated;
-- marketing_edit_v2.03_01_career_contract_raw



-- marketing_edit_v2.03_02_const_contract_raw
    -- 更新日：2025/8/26
    -- 作業者：K.ISOZUMI
    -- 更新内容：項目追加

/*
■実行内容
施工管理の事業部で管理している売上集計定義に則り、レコードを引用（当時"Staff-V"というシステムを活用していた）
施工管理に登録している派遣社員に対して、初回受注に着目し情報を整理
PK：id_invoice(紹介事業とはテーブル構造が異なり、現場が管理しているスプレッドシートから引用しているだけにすぎない)
*/

CREATE OR REPLACE TABLE `tryt-bigquery-pj.marketing_edit_v2.03_02_const_contract_raw` AS 
WITH 
    const_staff AS ( -- 派遣社員データを整理
        SELECT 
            staffCD
            , SFID AS cd__c
        FROM `tryt-bigquery-pj.sales_edit.const_00_staff`-- ★★★★★ 総務部/営業企画部 が管理しているスプレッドシートを参照しているが、そのスプレッドシートが担当者により更新されない限り、施工の情報も更新されないので注意すること https://docs.google.com/spreadsheets/d/183FfDQ6Gs5-kUSyXEXUcMSaVJid47BJ4gDV80Zd77iY/edit?gid=1571167581#gid=1571167581
        QUALIFY ROW_NUMBER() OVER (PARTITION BY staffCD) = 1 -- staffCDで一意とする
    ),

    const_hikiate_raw AS ( -- 契約期間/初回受注日を特定するために契約順を整理
        SELECT
            staffCD
            , DATE_DIFF(LAST_DAY(hakensyuryo)+1 , DATE_TRUNC(hakenkaishi , MONTH) , MONTH) AS kikan
            , seikyukingaku
            , juchubi
            , ROW_NUMBER() OVER(PARTITION BY staffCD ORDER BY juchubi ASC) AS juchu_flg
        FROM `tryt-bigquery-pj.sales_edit.const_00_hikiate` -- ★★★★★ 総務部/営業企画部 が管理しているスプレッドシートを参照しているが、そのスプレッドシートが担当者により更新されない限り、施工の契約情報も更新されないので注意すること https://docs.google.com/spreadsheets/d/1wgPUEA3MCjIuUHT0nqcTbP6bzrb4oYSpla3VCzErIU8/edit?gid=913444774#gid=913444774
        WHERE staffCD IS NOT NULL
    ),

    const_first_order AS ( -- 初回受注日に関するレコードのみを抽出し、初回受注からの指定リードタイム内での受注実績を集計
        SELECT
            t1.* EXCEPT(juchu_flg)
            , t2.juchubi AS f_juchubi --初回受注日
            , t1.juchu_flg
            , SUM(t1.seikyukingaku * t1.kikan) OVER(PARTITION BY t1.staffCD) AS total_amount
            , SUM(CASE WHEN t1.juchu_flg = 1 THEN t1.seikyukingaku * t1.kikan ELSE 0 END) OVER(PARTITION BY t1.staffCD) AS f_amount__c
            , SUM(CASE WHEN t1.juchubi BETWEEN t2.juchubi AND DATE_ADD(t2.juchubi , INTERVAL 6 MONTH) - 1 THEN t1.seikyukingaku * t1.kikan ELSE 0 END) OVER(PARTITION BY t1.staffCD) AS f_6_amount__c
            , SUM(CASE WHEN t1.juchubi BETWEEN t2.juchubi AND DATE_ADD(t2.juchubi , INTERVAL 12 MONTH) - 1 THEN t1.seikyukingaku * t1.kikan ELSE 0 END) OVER(PARTITION BY t1.staffCD) AS f_12_amount__c
            , SUM(CASE WHEN t1.juchubi BETWEEN t2.juchubi AND DATE_ADD(t2.juchubi , INTERVAL 24 MONTH) - 1 THEN t1.seikyukingaku * t1.kikan ELSE 0 END) OVER(PARTITION BY t1.staffCD) AS f_24_amount__c
        FROM const_hikiate_raw AS t1
        LEFT JOIN const_hikiate_raw AS t2
            ON t1.staffCD = t2.staffCD
                AND t2.juchu_flg = 1 --初回受注のレコードに限定する
    ),

    sfid_added AS ( -- 施工管理における売上情報に対してSFIDを突合
        SELECT
            CONCAT(t1.staffCD, '_', t1.f_juchubi) AS id_invoice -- このような形でPKとするしかないと想定 (250826 KI追記)
            , t2.cd__c
            , t1.staffCD
            , t3.owner_id
            , t1.f_juchubi AS record_date
            , DATE_TRUNC(t1.f_juchubi , MONTH) AS record_month_before_edit --計上書類チェック月に相当
            , t1.total_amount
            , t1.f_amount__c
            , t1.f_6_amount__c
            , t1.f_12_amount__c
            , t1.f_24_amount__c
        FROM const_first_order AS t1
        INNER JOIN const_staff AS t2
            ON t1.staffCD = t2.staffCD
              AND t2.cd__c IS NOT NULL
        LEFT JOIN `tryt-bigquery-pj.marketing_edit_v2.01_00_const_account_job_seeker_temp_field` t3
            ON t2.cd__c = t3.cd__c
        WHERE t1.juchu_flg = 1
    )

--最終集計
SELECT 
    *
FROM sfid_added;
-- marketing_edit_v2.03_02_const_contract_raw



-- marketing_edit_v2.01_05_02_record_raw
    -- 更新日：2026/07/17
    -- 作業者：細江
    -- 更新内容：タイムアウト（DEADLINE_EXCEEDED）エラーに伴うリファクタリング

/*
■実行内容
各ステップのアクション日について、求職者オブジェクト・コンタクト履歴・売上請求管理を突合し比較することで、求職者単位での接触日（登録日）以降最も早い日付を集計する (アクションに欠損が発生している場合は、後工程の日付を用いて便宜上補正する形で処理、この処理を行わないと欠損が生じたままのレコードになる)
また、24年1月時点で施工管理のKPI集計に必要なCVV(=conversion value)情報と、集客時点における求職者に関する価値付けであるスコア情報、その他入口時点での不変情報の突合を行う
(contact_dateがNULLの場合を除き、cd__c と contact_date と judge_entry_route により一意)
*/

CREATE OR REPLACE TABLE `tryt-bigquery-pj.marketing_edit_v2.01_05_02_record_raw` PARTITION BY contact_date CLUSTER BY entry_route AS 
WITH 
    record_raw AS ( -- 入口KPI集計における求職者情報を引用
        SELECT
            * EXCEPT(dummy_step1_from_js , dummy_step2_from_js , dummy_step3_from_js , dummy_step4_from_js , dummy_step5_from_js)
            , CASE WHEN contact_date IS NULL THEN NULL ELSE dummy_step1_from_js END AS dummy_step1_from_js                          -- 求職者OBJから取得したfirst_hearing__c 
            , CASE WHEN contact_date IS NULL THEN NULL ELSE dummy_step2_from_js END AS dummy_step2_from_js                          -- 求職者OBJから取得したjob_suggestion__c
            , CASE WHEN contact_date IS NULL THEN NULL ELSE dummy_step3_from_js END AS dummy_step3_from_js                          -- 求職者OBJから取得したdetermination_of_interview_date__c
            , CASE WHEN contact_date IS NULL THEN NULL ELSE dummy_step4_from_js END AS dummy_step4_from_js                          -- 求職者OBJから取得したinterview_implementation__c
            , CASE WHEN contact_date IS NULL THEN NULL ELSE dummy_step5_from_js END AS dummy_step5_from_js                          -- 求職者OBJから取得したagreement__c
        FROM `tryt-bigquery-pj.marketing_edit_v2.01_05_01_record_raw`                                                               -- 「通常KPI」+CRM再登録+NU経路を1つにユニオンしたテーブル
    ),

    action_history AS ( -- コンタクト履歴を cd__c 単位で事前集約（ARRAY化）
        SELECT
            cd__c
            , ARRAY_AGG(STRUCT(created_date, action_category0_5, action_category, type) ORDER BY created_date ASC) AS arr_actions
        FROM `tryt-bigquery-pj.marketing_edit_v2.02_01_career_const_action_aggregated`
        WHERE cd__c IS NOT NULL
        GROUP BY cd__c
    ),

    earliest_action_task_calc AS ( -- 配列に対する相関サブクエリで各アクションの最古日を抽出
        SELECT
            t1.flg
            , (SELECT MIN(a.created_date) FROM UNNEST(t2.arr_actions) a WHERE t1.contact_date <= a.created_date AND a.action_category0_5 = 'step0.5') AS earliest_step0_5_from_task
            , (SELECT MIN(a.created_date) FROM UNNEST(t2.arr_actions) a WHERE t1.contact_date <= a.created_date AND a.action_category = 'step1') AS earliest_step1_from_task
            , (SELECT MIN(a.created_date) FROM UNNEST(t2.arr_actions) a 
               WHERE t1.contact_date <= a.created_date AND a.action_category = 'step2' 
                 AND ( (t1.occupation NOT IN ('施工管理','介護派遣','保育派遣') AND a.type = '紹介') OR (t1.occupation IN ('施工管理','介護派遣','保育派遣') AND a.type = '派遣') )
              ) AS earliest_step2_from_task
            , (SELECT MIN(a.created_date) FROM UNNEST(t2.arr_actions) a 
               WHERE t1.contact_date <= a.created_date AND a.action_category = 'step3' 
                 AND ( (t1.occupation NOT IN ('施工管理','介護派遣','保育派遣') AND a.type = '紹介') OR (t1.occupation IN ('施工管理','介護派遣','保育派遣') AND a.type = '派遣') )
              ) AS earliest_step3_from_task
            , (SELECT MIN(a.created_date) FROM UNNEST(t2.arr_actions) a 
               WHERE t1.contact_date <= a.created_date AND a.action_category = 'step4' 
                 AND ( (t1.occupation NOT IN ('施工管理','介護派遣','保育派遣') AND a.type = '紹介') OR (t1.occupation IN ('施工管理','介護派遣','保育派遣') AND a.type = '派遣') )
              ) AS earliest_step4_from_task
            , (SELECT MIN(a.created_date) FROM UNNEST(t2.arr_actions) a 
               WHERE t1.contact_date <= a.created_date AND a.action_category = 'step5' 
                 AND ( (t1.occupation NOT IN ('施工管理','介護派遣','保育派遣') AND a.type = '紹介') OR (t1.occupation IN ('施工管理','介護派遣','保育派遣') AND a.type = '派遣') )
              ) AS earliest_step5_from_task
        FROM `tryt-bigquery-pj.marketing_edit_v2.01_05_01_record_raw` AS t1
        LEFT JOIN action_history AS t2
            ON t1.cd__c = t2.cd__c
    ),

    earliest_action_task AS (
        SELECT
            flg
            , MIN(earliest_step0_5_from_task) AS earliest_step0_5_from_task
            , MIN(earliest_step1_from_task) AS earliest_step1_from_task
            , MIN(earliest_step2_from_task) AS earliest_step2_from_task
            , MIN(earliest_step3_from_task) AS earliest_step3_from_task
            , MIN(earliest_step4_from_task) AS earliest_step4_from_task
            , MIN(earliest_step5_from_task) AS earliest_step5_from_task
        FROM earliest_action_task_calc
        GROUP BY flg
        HAVING (
            earliest_step0_5_from_task IS NULL
            AND earliest_step1_from_task IS NULL
            AND earliest_step2_from_task IS NULL
            AND earliest_step3_from_task IS NULL
            AND earliest_step4_from_task IS NULL
            AND earliest_step5_from_task IS NULL
        ) = FALSE
    ),

    career_flg_added AS ( -- 紹介事業における成約情報に対して、求職者情報の「フラグ」を突合
        SELECT
            t1.*
            , t2.flg -- t2.flgは、marketing_edit_v2.01_05_01_record_raw においてCONCAT(CONCAT(t1.cd__c , t1.contact_date) , t1.judge_entry_route)で生成されている ex.) SF029415452023-04-271年以内
            , ROW_NUMBER() OVER(PARTITION BY t2.flg ORDER BY t1.record_date ASC) AS record_contact_rank
        FROM `tryt-bigquery-pj.marketing_edit_v2.03_01_career_contract_raw` AS t1
        LEFT JOIN record_raw AS t2
            ON t1.cd__c = t2.cd__c
                AND t1.record_date >= t2.contact_date
        WHERE t1.gross_flg = 1          --marketing_edit_v2.03_01_career_contract_rawにおいて生成される、グロス売上集計用フラグ
            AND t1.contract_count = 1   --marketing_edit_v2.03_01_career_contract_rawにおいて生成される、成約数カウント用のフラグ
    ),

    const_flg_added AS ( -- 施工管理における成約情報に対して、求職者情報の「フラグ」を突合
        SELECT
            t1.*
            , t2.flg -- t2.flgは、marketing_edit_v2.01_05_01_record_raw においてCONCAT(CONCAT(t1.cd__c , t1.contact_date) , t1.judge_entry_route)で生成されている ex.) SF029415452023-04-271年以内
            , ROW_NUMBER() OVER(PARTITION BY t2.flg ORDER BY t1.record_date ASC) AS record_contact_rank
        FROM `tryt-bigquery-pj.marketing_edit_v2.03_02_const_contract_raw` AS t1
        LEFT JOIN record_raw AS t2
            ON t1.cd__c = t2.cd__c
                AND t1.record_date >= t2.contact_date
    ),

    step_correction1 AS ( -- 求職者毎の接触日（登録日）以降、求職者OBJおよびコンタクト履歴の両方から集計した際に最も早いアクション日の情報を整形する ★★★コンタクト履歴の値が欠損等により取得できない場合があるので、求職者OBJから取得した値と比較し、最も早いアクション日を集計する必要がある
        SELECT
            t1.* EXCEPT(dummy_step1_from_js , dummy_step2_from_js , dummy_step3_from_js , dummy_step4_from_js , dummy_step5_from_js)
            , t3.expected_date_of_employment__c         -- 入職予定日
            , IFNULL(t2.earliest_step0_5_from_task, DATE('5000-01-01')) AS step0_5_to_be_fixed
            , LEAST(
                        CASE 
                            WHEN t1.dummy_step1_from_js IS NULL OR t1.dummy_step1_from_js < t1.contact_date THEN DATE('5000-01-01') 
                            ELSE t1.dummy_step1_from_js -- 求職者OBJから取得したfirst_hearing__c 
                        END 
                        , IFNULL(t2.earliest_step1_from_task, DATE('5000-01-01'))
                    ) 
            AS step1_to_be_fixed
            , LEAST(
                        CASE 
                            WHEN t1.dummy_step2_from_js IS NULL OR t1.dummy_step2_from_js < t1.contact_date THEN DATE('5000-01-01') 
                            ELSE t1.dummy_step2_from_js -- 求職者OBJから取得したjob_suggestion__c
                        END 
                        , IFNULL(t2.earliest_step2_from_task, DATE('5000-01-01'))
                    ) 
            AS step2_to_be_fixed
            , LEAST(
                        CASE 
                            WHEN t1.dummy_step3_from_js IS NULL OR t1.dummy_step3_from_js < t1.contact_date THEN DATE('5000-01-01') 
                            ELSE t1.dummy_step3_from_js -- 求職者OBJから取得したdetermination_of_interview_date__c
                        END 
                        , IFNULL(t2.earliest_step3_from_task, DATE('5000-01-01'))
                    ) 
            AS step3_to_be_fixed
            , LEAST(
                        CASE 
                            WHEN t1.dummy_step4_from_js IS NULL OR t1.dummy_step4_from_js < t1.contact_date THEN DATE('5000-01-01') 
                            ELSE t1.dummy_step4_from_js -- 求職者OBJから取得したinterview_implementation__c
                        END 
                        , IFNULL(t2.earliest_step4_from_task, DATE('5000-01-01'))
                    ) 
            AS step4_to_be_fixed
            , CASE 
                WHEN t3.record_date IS NOT NULL THEN t3.record_date -- 03_01_career_contract_raw における計上書類チェック日を引用
                WHEN t4.record_date IS NOT NULL THEN t4.record_date -- 03_02_const_contract_rawにおけるf_juchubiを引用
                ELSE LEAST
                    (
                        CASE 
                            WHEN t1.dummy_step5_from_js IS NULL OR t1.dummy_step5_from_js < t1.contact_date THEN DATE('5000-01-01') 
                            ELSE t1.dummy_step5_from_js -- 求職者OBJから取得したagreement__c
                        END  
                        , IFNULL(t2.earliest_step5_from_task, DATE('5000-01-01'))
                    ) 
            END AS step5_to_be_fixed
            , CASE 
                WHEN t3.record_date IS NOT NULL THEN t3.record_date 
                WHEN t4.record_date IS NOT NULL THEN t4.record_date 
                ELSE NULL 
            END AS record_date
            , t3.retire_date
            , t3.retire_category                -- 辞退退職情報
            , t3.retire_leadtime                -- 入職予定日に対して辞退/退職がどの程度離れているかを集計
        FROM record_raw AS t1                   -- marketing_edit_v2.01_05_01_record_raw (「通常KPI」+CRM再登録+NU経路を1つにユニオンしたテーブル)
        LEFT JOIN earliest_action_task AS t2    -- 入口の集計対象となるレコードにおいて、コンタクト履歴から取得した、接触日（登録日）後の最も早い各アクションが集計されたテーブル
            ON t1.flg = t2.flg                  -- t1.flg/t2.flgのいずれも、marketing_edit_v2.01_05_01_record_raw においてCONCAT(CONCAT(t1.cd__c , t1.contact_date) , t1.judge_entry_route)で生成されている ex.) SF029415452023-04-271年以内
        LEFT JOIN career_flg_added AS t3        -- 医療福祉事業における成約情報
            ON t1.flg = t3.flg                  -- t1.flg/t3.flgのいずれも、marketing_edit_v2.01_05_01_record_raw においてCONCAT(CONCAT(t1.cd__c , t1.contact_date) , t1.judge_entry_route)で生成されている ex.) SF029415452023-04-271年以内
                AND t3.record_contact_rank = 1  -- career_flg_added において、ROW_NUMBER() OVER(PARTITION BY t2.flg ORDER BY t1.record_date ASC)で生成されている
                AND t1.occupation <> '施工管理' 
        LEFT JOIN const_flg_added AS t4        -- 施工管理における成約情報
            ON t1.flg = t4.flg                  -- t1.flg/t4.flgのいずれも、marketing_edit_v2.01_05_01_record_raw においてCONCAT(CONCAT(t1.cd__c , t1.contact_date) , t1.judge_entry_route)で生成されている ex.) SF029415452023-04-271年以内
                AND t4.record_contact_rank = 1  -- const_flg_added において、ROW_NUMBER() OVER(PARTITION BY t2.flg ORDER BY t1.record_date ASC)で生成されている
                AND t1.occupation = '施工管理'   
    ),

    step_correction2 AS ( -- 求職者テーブルにおいて、各ステップの日付情報における欠損を補正(ex.「面接設定日」のレコードがSFに無い(CAが入力を忘れている)が、「面接実施日」のレコードがSFに有る場合、ステップ3=「面接設定日」が欠損してしまうので、「面接実施日」の日付を代入する)
        SELECT
            * EXCEPT(step0_5_to_be_fixed , step1_to_be_fixed , step2_to_be_fixed , step3_to_be_fixed , step4_to_be_fixed , step5_to_be_fixed)
            , CASE 
                WHEN LEAST(step0_5_to_be_fixed , step1_to_be_fixed , step2_to_be_fixed , step3_to_be_fixed , step4_to_be_fixed , step5_to_be_fixed) = DATE('5000-01-01') THEN NULL 
                ELSE LEAST(step0_5_to_be_fixed , step1_to_be_fixed , step2_to_be_fixed , step3_to_be_fixed , step4_to_be_fixed , step5_to_be_fixed) 
            END AS step0_5
            , CASE 
                WHEN LEAST(step1_to_be_fixed , step2_to_be_fixed , step3_to_be_fixed , step4_to_be_fixed , step5_to_be_fixed) = DATE('5000-01-01') THEN NULL 
                ELSE LEAST(step1_to_be_fixed , step2_to_be_fixed , step3_to_be_fixed , step4_to_be_fixed , step5_to_be_fixed) 
            END AS step1
            , CASE 
                WHEN LEAST(step2_to_be_fixed , step3_to_be_fixed , step4_to_be_fixed , step5_to_be_fixed) = DATE('5000-01-01') THEN NULL 
                ELSE LEAST(step2_to_be_fixed , step3_to_be_fixed , step4_to_be_fixed , step5_to_be_fixed) 
            END AS step2
            , CASE 
                WHEN LEAST(step3_to_be_fixed , step4_to_be_fixed , step5_to_be_fixed) = DATE('5000-01-01') THEN NULL 
                ELSE LEAST(step3_to_be_fixed , step4_to_be_fixed , step5_to_be_fixed) 
            END AS step3
            , CASE 
                WHEN LEAST(step4_to_be_fixed , step5_to_be_fixed) = DATE('5000-01-01') THEN NULL 
                ELSE LEAST(step4_to_be_fixed , step5_to_be_fixed) 
            END AS step4
            , CASE 
                WHEN step5_to_be_fixed = DATE('5000-01-01') THEN NULL 
                ELSE step5_to_be_fixed 
            END AS step5
        FROM step_correction1
    ),

    entrance_info_int AS ( -- 入口の項目を整形
        SELECT
            t1.*
            , CASE WHEN t1.occupation = '施工管理' THEN t3.sex__c ELSE t2.sex__c END AS sex__c
        FROM step_correction2 AS t1
        LEFT JOIN `tryt-bigquery-pj.marketing_edit_v2.01_00_career_account_job_seeker_temp_field` AS t2
            ON t1.cd__c = t2.cd__c
        LEFT JOIN `tryt-bigquery-pj.marketing_edit_v2.01_00_const_account_job_seeker_temp_field` AS t3
            ON t1.cd__c = t3.cd__c
    ),

    cvv_int AS ( -- CVV(=conversion value)情報を追加する。 セグメントにおける定義に変更があった場合は、本クエリにおける引用条件を修正すること
        SELECT
            t1.*
            , CASE 
                WHEN t2.cvv IS NULL THEN 1 
                ELSE t2.cvv 
            END AS cvv
            , CASE 
                WHEN t2.n_cvv IS NULL THEN 1 
                ELSE t2.n_cvv 
            END AS n_cvv
        FROM entrance_info_int AS t1
        LEFT JOIN `tryt-bigquery-pj.production_tryt.master_cvv_parameter` AS t2 -- CVV情報のマスタ(24年1月現在では、各四半期毎に、代理店向けCSVファイルから集計し更新する建付けとなっている) https://docs.google.com/spreadsheets/d/1tVy_iOad8mgyKCzG3XVbcKyyphGx0dosTHpRBb9DR80/edit?pli=1&gid=1431743958#gid=1431743958
            ON t1.occupation = '施工管理'
                AND t1.occupation = t2.occupation
                AND t1.entry_route = t2.entry_route
                AND t1.medium = t2.medium
                AND CASE 
                        WHEN t1.age_group IS NULL THEN '不明' 
                        ELSE t1.age_group 
                    END = t2.age_group
                AND CASE 
                        WHEN t1.experience_in_construction_management__c = 1 THEN 'あり' 
                        WHEN t1.experience_in_construction_management__c = 0 THEN 'なし' 
                        ELSE '不明' 
                    END = t2.exp
    ),

    score_raw AS ( -- DX推進室作成によるスコア予測用のテーブルを引用
        SELECT
            cd__c, contact_date, category, occupation  -- cvv_int との結合キー
            , step3_pred                         -- 想定ステップ3転換確率(代理店向けCSVファイルでの名称：ステップ3転換確率_AI予測モデル)
            , expected_sales                     -- 想定売上価値(代理店向けCSVファイルでの名称：想定売上_AI予測モデル)
            , step3_pred_divided_by_mean         -- 獲得時点求職者価値（対セグメント平均）(代理店向けCSVファイルでの名称：CVV_AI予測モデル)
            , modified_gross_expected_sales      -- 想定売上価値(代理店向けCSVファイルでの名称：想定グロス売上(修正版)_AI予測モデル)
            , ROW_NUMBER() OVER(PARTITION BY cd__c , contact_date , category , occupation ORDER BY expected_sales DESC) AS score_flg
        FROM `tryt-dx-team.closing_rate_prediction.scores_by_entrance_info`
    ),

    score_raw_v2 AS ( -- DX推進室作成によるスコア予測用V2テーブルを引用
        SELECT
            cd__c, contact_date, category, occupation  -- cvv_int との結合キー
            , step3_pred                         -- 想定ステップ3転換確率v2
            , expected_sales                     -- 想定売上価値v2
            , expected_sales_v3                  -- 想定売上価値v3,20260915山崎追記
            , ROW_NUMBER() OVER(PARTITION BY cd__c , contact_date , category , occupation ORDER BY expected_sales DESC) AS score_flg
        FROM `tryt-dx-team.closing_rate_prediction_v2.scores_by_entrance_info`
    ),

    score_int AS ( -- 予測スコアを突合
        SELECT
            t1.*
            , t2.step3_pred                           -- 想定ステップ3転換確率(代理店向けCSVファイルでの名称：ステップ3転換確率_AI予測モデル)
            , t2.expected_sales                       -- 想定売上価値(代理店向けCSVファイルでの名称：想定売上_AI予測モデル)
            , t2.step3_pred_divided_by_mean           -- 獲得時点求職者価値（対セグメント平均）(代理店向けCSVファイルでの名称：CVV_AI予測モデル)
            , t2.modified_gross_expected_sales        -- 想定売上価値(代理店向けCSVファイルでの名称：想定グロス売上(修正版)_AI予測モデル)
            , t3.step3_pred AS step3_pred_v2          -- 想定ステップ3転換確率v2
            , t3.expected_sales AS expected_sales_v2  -- 想定売上価値v2
            , t3.expected_sales_v3 -- 想定売上価値v3,20260915山崎追記
        FROM cvv_int AS t1
        LEFT JOIN score_raw AS t2
            ON t1.cd__c = t2.cd__c
                AND t1.contact_date = t2.contact_date
                AND CASE 
                        WHEN t1.entry_route = 'CRM' AND t1.judge_entry_route LIKE '%再登録%' AND t1.judge_entry_route NOT LIKE '%LINE%' AND t1.judge_entry_route NOT LIKE '%友人紹介%' THEN 'CRM再登録'
                        WHEN t1.entry_route = 'NU' THEN 'NU経路'
                        ELSE '通常KPI' 
                    END = t2.category
                AND t1.occupation = t2.occupation
                AND t2.score_flg = 1
        LEFT JOIN score_raw_v2 AS t3
            ON t1.cd__c = t3.cd__c
                AND t1.contact_date = t3.contact_date
                AND CASE 
                        WHEN t1.entry_route = 'CRM' AND t1.judge_entry_route LIKE '%再登録%' AND t1.judge_entry_route NOT LIKE '%LINE%' AND t1.judge_entry_route NOT LIKE '%友人紹介%' THEN 'CRM再登録'
                        WHEN t1.entry_route = 'NU' THEN 'NU経路'
                        ELSE '通常KPI' 
                    END = t3.category
                AND t1.occupation = t3.occupation
                AND t3.score_flg = 1
    )

--最終集計
SELECT
    *
FROM score_int;
-- marketing_edit_v2.01_05_02_record_raw



-- marketing_edit_v2.03_03_career_contract_processed
    -- 更新日：2026/07/17
    -- 作業者：細江
    -- 更新内容：タイムアウト（DEADLINE_EXCEEDED）エラーに伴うリファクタリング

/*
■実行内容
★★★どの経路が成約に寄与したかを判定する 下記による判定順位で経路が決定される★★★
(PK:id_invoice)

1.登録日から3か月以内に成約のレコードがある場合         　      ⇒広告・SEO・通常CRM経由として判定する
2.CRM再登録から7日以内にヒアリング転換のレコードがある場合       ⇒CRM再登録経由として判定する
3.NU⇒営業連携から7日以内にヒアリング転換のレコードがある場合     ⇒NU経由として判定する
4.成約から遡り3カ月以内にCRM再登録のレコードがある場合          ⇒CRM再登録経由として判定する
5.成約から遡り3カ月以内にNU⇒営業連携のレコードがある場合        ⇒NU経由として判定する
6.上記のいずれにも該当しない場合に、経路を不明とする
*/


CREATE OR REPLACE TABLE `tryt-bigquery-pj.marketing_edit_v2.03_03_career_contract_processed` AS 
WITH 
    contract_amount AS (
        SELECT
            *
        FROM
            (
                -- 既存の条件(marketing_edit_v2.00_01_02_workday_for_invoiceの引用元のworkdayマスタのworkday_calculation_thismonth_2が誤りを含むため、2025年3月分の売上までの適用とする ※経営陣判断により250424条件変更)
                SELECT
                    t1.* EXCEPT(record_date)
                    , t2.occupation
                    , t4.kyotencd 
                    , t1.record_date                                                                        -- 計上書類チェック日
                    , CASE 
                        WHEN DATE_ADD(DATE_TRUNC(t3.calendar_date , MONTH) , INTERVAL - 1 MONTH) IS NULL THEN t1.record_month_before_edit --翌月2営業日のみ抜粋したテーブルに当該計上日が存在しないならば、通常の計上書類チェック月 を出力する(ex.「10/15 計上」は 翌月2営業日のみ抜粋したテーブルに存在しないので、「2024年10月」 を出力)
                        ELSE DATE_ADD(DATE_TRUNC(t3.calendar_date , MONTH) , INTERVAL - 1 MONTH)            -- 翌月2営業日のみ抜粋したテーブルに当該計上日が存在するならば、【計上日を丸めた月 -1】月を出力する(ex.「10/2 計上」は 翌月2営業日のみ抜粋したテーブルに存在するので、「2024年9月」を出力 )
                    END AS record_month                                                                     -- ★★★★★営業日を判定するテーブルの中で2営業日以内の日付と紐づくrecord_date（計上日）は前月計上とする = 翌月1営/2営 における計上は前月分として補正する ex) 「10/2 計上」のレコードは9月分として集計される ★★★★★
                FROM `tryt-bigquery-pj.marketing_edit_v2.03_01_career_contract_raw` t1
                LEFT JOIN `tryt-bigquery-pj.production_tryt.master_branch` AS t2                            -- 拠点マスタ https://docs.google.com/spreadsheets/d/1tVy_iOad8mgyKCzG3XVbcKyyphGx0dosTHpRBb9DR80/edit?gid=1094227535#gid=1094227535
                    ON t1.branch_text__c = t2.branch
                LEFT JOIN `tryt-bigquery-pj.marketing_edit_v2.00_01_02_workday_for_invoice` AS t3           -- ★★★営業日判定用マスタにおいて、翌月2営業日のみのみ抜粋したテーブル(翌月2営業日までの計上承認は前月の計上として処理をするルールが存在) https://docs.google.com/spreadsheets/d/1tVy_iOad8mgyKCzG3XVbcKyyphGx0dosTHpRBb9DR80/edit?gid=1687421902#gid=1687421902
                    ON t1.record_date = t3.calendar_date
                LEFT JOIN `tryt-bigquery-pj.production_tryt.master_sales_office` AS t4                      -- 営業所マスタ https://docs.google.com/spreadsheets/d/1se4E_tSOTM50Td9WsTmpYhpLd3_CIYQMjYT36uupTVc/edit?gid=1620852360#gid=1620852360
                    ON t1.department_in_charge__c = t4.branch_flag
                WHERE DATE_ADD(t1.record_date, INTERVAL -2 MONTH) <= t1.accounting_receipt_date__c
                    AND t2.occupation IS NOT NULL
                    AND t1.record_date <= DATE('2025-04-02')                                                -- 計上書類チェック日
                UNION ALL

                -- 計上書類チェック日が2025/4/3 ~ 2025/4/30 の場合、2025年4月分の売上はmaster_sales_dateの計上書類チェック日と紐づけ、売上月はsales_dateとする ※経営陣判断により250424条件変更
                -- 計上書類チェック日が2025/5/1以降の場合、2025年5月以降の売上はmaster_sales_dateの営業承認日と紐づけ、売上月はsales_dateとする ※経営陣判断により250424条件変更
                SELECT
                    t1.* EXCEPT(record_date)
                    , t2.occupation
                    , t4.kyotencd 
                    , CASE
                        WHEN t1.record_date BETWEEN DATE('2025-04-03') AND DATE('2025-04-30') THEN t1.record_date
                        ELSE t3.accounting_receipt_date__c 
                    END AS record_date                                         
                    , DATE_TRUNC(t3.sales_date, MONTH) AS record_month
                FROM `tryt-bigquery-pj.marketing_edit_v2.03_01_career_contract_raw` t1
                LEFT JOIN `tryt-bigquery-pj.production_tryt.master_branch` AS t2                            -- 拠点マスタ https://docs.google.com/spreadsheets/d/1tVy_iOad8mgyKCzG3XVbcKyyphGx0dosTHpRBb9DR80/edit?gid=1094227535#gid=1094227535
                    ON t1.branch_text__c = t2.branch
                LEFT JOIN `tryt-bigquery-pj.production_tryt.master_sales_date` AS t3                        -- 【重要】営業日マスタ(営業本部にて管理しているのでこちらを正として運用すること) https://docs.google.com/spreadsheets/d/1se4E_tSOTM50Td9WsTmpYhpLd3_CIYQMjYT36uupTVc/edit?gid=559861048#gid=559861048
                    ON CASE
                        WHEN t1.record_date BETWEEN DATE('2025-04-03') AND DATE('2025-04-30') THEN t1.record_date = t3.documents_check_date__c  
                        ELSE t1.accounting_receipt_date__c = t3.accounting_receipt_date__c  
                    END
                LEFT JOIN `tryt-bigquery-pj.production_tryt.master_sales_office` AS t4                      -- 営業所マスタ https://docs.google.com/spreadsheets/d/1se4E_tSOTM50Td9WsTmpYhpLd3_CIYQMjYT36uupTVc/edit?gid=1620852360#gid=1620852360
                    ON t1.department_in_charge__c = t4.branch_flag
                WHERE DATE_ADD(t1.record_date, INTERVAL -2 MONTH) <= t1.accounting_receipt_date__c
                    AND t2.occupation IS NOT NULL
                    AND t1.record_date >= DATE('2025-04-03')                                                --計上書類チェック日
                UNION ALL

                -- 計上書類チェック日が5/1-5/13 AND 営業承認日が3/29-4/30 であるならば、売上月は2025年4月とする ※経営陣判断により250514条件変更
                SELECT
                    t1.* EXCEPT(record_date)
                    , t2.occupation
                    , t4.kyotencd 
                    , t1.record_date                                          
                    , '2025-04-01' AS record_month
                FROM `tryt-bigquery-pj.marketing_edit_v2.03_01_career_contract_raw` t1
                LEFT JOIN `tryt-bigquery-pj.production_tryt.master_branch` AS t2                            -- 拠点マスタ https://docs.google.com/spreadsheets/d/1tVy_iOad8mgyKCzG3XVbcKyyphGx0dosTHpRBb9DR80/edit?gid=1094227535#gid=1094227535
                    ON t1.branch_text__c = t2.branch
                LEFT JOIN `tryt-bigquery-pj.production_tryt.master_sales_office` AS t4                      -- 営業所マスタ https://docs.google.com/spreadsheets/d/1se4E_tSOTM50Td9WsTmpYhpLd3_CIYQMjYT36uupTVc/edit?gid=1620852360#gid=1620852360
                    ON t1.department_in_charge__c = t4.branch_flag
                WHERE DATE_ADD(t1.record_date, INTERVAL -2 MONTH) <= t1.accounting_receipt_date__c
                    AND t2.occupation IS NOT NULL
                    AND t1.record_date BETWEEN DATE('2025-05-01') AND DATE('2025-05-13')                    -- 計上書類チェック日
                    AND t1.accounting_receipt_date__c BETWEEN DATE('2025-03-29') AND DATE('2025-04-30')     -- 営業承認日
            )
        WHERE record_month >= target_start_date
    ),    

    record_raw_history AS (
        SELECT 
            cd__c
            , ARRAY_AGG(STRUCT(contact_date, contact_month1, entry_route, judge_entry_route, step1) ORDER BY contact_date DESC) AS arr_history
        FROM `tryt-bigquery-pj.marketing_edit_v2.01_05_02_record_raw`
        WHERE cd__c IS NOT NULL
        GROUP BY cd__c
    ),

    normal_classified AS ( -- 広告・SEO・通常CRM 経由のレコード
        SELECT
            t1.invoice_name
            , t2.contact_date
            , t2.contact_month1
            , t2.entry_route
            , t2.judge_entry_route
            , CASE 
                WHEN DATE_ADD(t2.contact_date , INTERVAL 3 MONTH) > t1.record_date THEN 1  --登録日から3ヵ月以内に計上されていればMK経由と判定
                ELSE 0 
            END AS marketing_route 
        FROM contract_amount AS t1
        LEFT JOIN record_raw_history AS t_hist
            ON t1.cd__c = t_hist.cd__c
        CROSS JOIN UNNEST(ARRAY(
            SELECT AS STRUCT h.contact_date, h.contact_month1, h.entry_route, h.judge_entry_route
            FROM UNNEST(t_hist.arr_history) AS h
            WHERE h.contact_date <= t1.record_date
                AND h.entry_route <> 'NU'
                AND NOT (h.entry_route = 'CRM' AND h.judge_entry_route LIKE '%再登録%' AND h.judge_entry_route NOT LIKE '%LINE%' AND h.judge_entry_route NOT LIKE '%友人紹介%')
            ORDER BY h.contact_date DESC
            LIMIT 1
        )) AS t2
        WHERE t1.record_rank = 1
    ),

    crm_classified AS ( -- CRM再登録 経由のレコード
        SELECT
            t1.invoice_name
            , t2.contact_date
            , t2.contact_month1
            , t2.entry_route
            , t2.judge_entry_route
            , CASE 
                WHEN t2.contact_date + 7 >= t2.step1 THEN 1                               -- CRM再登録後7日以内にヒアリング転換の場合
                WHEN DATE_ADD(t2.contact_date , INTERVAL 3 MONTH) > t1.record_date THEN 2 -- 成約から遡り3カ月以内にCRM再登録のレコードがある場合
                ELSE 0 
            END AS crm_marketing_route
        FROM contract_amount AS t1
        LEFT JOIN record_raw_history AS t_hist
            ON t1.cd__c = t_hist.cd__c
        CROSS JOIN UNNEST(ARRAY(
            SELECT AS STRUCT h.contact_date, h.contact_month1, h.entry_route, h.judge_entry_route, h.step1
            FROM UNNEST(t_hist.arr_history) AS h
            WHERE h.contact_date <= t1.record_date
                AND h.entry_route = 'CRM'
                AND h.judge_entry_route LIKE '%再登録%'
                AND h.judge_entry_route NOT LIKE '%LINE%' 
                AND h.judge_entry_route NOT LIKE '%友人紹介%'
            ORDER BY h.contact_date DESC
            LIMIT 1
        )) AS t2
        WHERE t1.record_rank = 1
    ),

    nu_classified AS ( -- NU 経由のレコード
        SELECT
            t1.invoice_name
            , t2.contact_date
            , t2.contact_month1
            , t2.entry_route
            , t2.judge_entry_route
            , CASE 
                WHEN t2.contact_date + 7 >= t2.step1 THEN 1                               -- NU⇒営業連携から7日以内にヒアリング転換の場合
                WHEN DATE_ADD(t2.contact_date , INTERVAL 3 MONTH) > t1.record_date THEN 2 -- 成約から遡り3カ月以内にNU⇒営業連携のレコードがある場合
                ELSE 0 
            END AS nu_marketing_route
        FROM contract_amount AS t1
        LEFT JOIN record_raw_history AS t_hist
            ON t1.cd__c = t_hist.cd__c
        CROSS JOIN UNNEST(ARRAY(
            SELECT AS STRUCT h.contact_date, h.contact_month1, h.entry_route, h.judge_entry_route, h.step1
            FROM UNNEST(t_hist.arr_history) AS h
            WHERE h.contact_date <= t1.record_date
                AND h.entry_route = 'NU' 
                AND h.contact_date IS NOT NULL 
            ORDER BY h.contact_date DESC
            LIMIT 1
        )) AS t2
        WHERE t1.record_rank = 1
    ),

    route_judged AS ( -- ★★★成約情報に対して求職者情報を突合し、どの経路により成約に至ったかを判定する
        SELECT
            t1.id_invoice
            , t1.invoice_name
            , t1.cd__c
            , t2.marketing_route
            , t1.occupation
            , t1.branch_text__c AS branch                                   -- 20250612追加: 01_09_03 への追加用
            , t1.kyotencd
            , t1.facility_name__c
            , t1.contract_count
            , t1.sales_name__c
            , t1.sales_amount__c
            , t1.gross_flg
            , t1.retire_date
            , t1.retire_category
            , t1.retire_leadtime
            , t1.created_date
            , t1.accounting_receipt_date__c 
            , t1.record_date
            , t1.record_month
            , CASE 
                WHEN t2.marketing_route = 1 THEN t2.contact_date            --広告・SEO・通常CRMのレコード
                WHEN t3.crm_marketing_route = 1 THEN t3.contact_date        --CRM再登録のレコード
                WHEN t4.nu_marketing_route = 1 THEN t4.contact_date         --NUのレコード
                WHEN t3.crm_marketing_route = 2 THEN t3.contact_date        --CRM再登録のレコード
                WHEN t4.nu_marketing_route = 2 THEN t4.contact_date         --NUのレコード
                ELSE GREATEST(IFNULL(t2.contact_date, DATE('1000-01-01')), IFNULL(t3.contact_date, DATE('1000-01-01')), IFNULL(t4.contact_date, DATE('1000-01-01'))) 
            END AS contact_date
            , CASE 
                WHEN t2.marketing_route = 1 THEN t2.contact_month1          --広告・SEO・通常CRMのレコード
                WHEN t3.crm_marketing_route = 1 THEN t3.contact_month1      --CRM再登録のレコード
                WHEN t4.nu_marketing_route = 1 THEN t4.contact_month1       --NUのレコード
                WHEN t3.crm_marketing_route = 2 THEN t3.contact_month1      --CRM再登録のレコード
                WHEN t4.nu_marketing_route = 2 THEN t4.contact_month1       --NUのレコード
                ELSE GREATEST(IFNULL(t2.contact_month1, DATE('1000-01-01')), IFNULL(t3.contact_month1, DATE('1000-01-01')), IFNULL(t4.contact_month1, DATE('1000-01-01'))) 
            END AS contact_month
            , CASE 
                WHEN t2.marketing_route = 1 THEN t2.entry_route             --広告・SEO・通常CRMのレコード
                ELSE 'CRM' 
            END AS status --★★★★★出口における経路分類に活用している(接触日から3ヵ月以内に計上されていればMK経由と判定し1のフラグが立つ、MK経由で無いと判定されたら"CRM"とする)★★★★★
            , CASE 
                WHEN t2.marketing_route = 1 THEN t2.judge_entry_route       --広告・SEO・通常CRMのレコード
                WHEN t3.crm_marketing_route = 1 THEN t3.judge_entry_route   --CRM再登録のレコード
                WHEN t4.nu_marketing_route = 1 THEN 'NU経路'                --NUのレコード
                WHEN t3.crm_marketing_route = 2 THEN t3.judge_entry_route   --CRM再登録のレコード
                WHEN t4.nu_marketing_route = 2 THEN 'NU経路'                --NUのレコード
                ELSE '不明' 
            END AS judge_entry_route_fixed --★★出口における経路分類に活用している
            , CASE 
                WHEN t2.marketing_route = 1 THEN t2.entry_route             --広告・SEO・通常CRMのレコード
                ELSE NULL 
            END AS entry_route
            , CASE 
                WHEN t2.marketing_route = 1 THEN t2.judge_entry_route       --広告・SEO・通常CRMのレコード
                ELSE NULL 
            END AS judge_entry_route
            , t1.record_type_id
            , t1.cancellation_type__c
            , t1.expected_date_of_employment__c
        FROM contract_amount t1
        LEFT JOIN normal_classified AS t2   --広告・SEO・通常CRMのレコード
            ON t1.invoice_name = t2.invoice_name
        LEFT JOIN crm_classified AS t3      --CRM再登録のレコード
            ON t1.invoice_name = t3.invoice_name
        LEFT JOIN nu_classified AS t4       --NUのレコード
            ON t1.invoice_name = t4.invoice_name
    )

--最終集計
SELECT
    *
FROM route_judged;
-- marketing_edit_v2.03_03_career_contract_processed



-- marketing_edit_v2.03_04_const_contract_processed
    -- 更新日：2026/07/17
    -- 作業者：細江
    -- 更新内容：タイムアウト（DEADLINE_EXCEEDED）エラーに伴うリファクタリング

/*
■実行内容
★★★施工管理において、どの経路が成約に寄与したかを判定する 下記による判定順位で経路が決定される★★★
紹介事業のロジックに倣う形に変更(250507)
(PK：id_invoice)

1.登録日から3か月以内に成約のレコードがある場合         　      ⇒広告・SEO・通常CRM経由として判定する
2.CRM再登録から7日以内にヒアリング転換のレコードがある場合       ⇒CRM再登録経由として判定する
3.成約から遡り3カ月以内にCRM再登録のレコードがある場合          ⇒CRM再登録経由として判定する
4.上記のいずれにも該当しない場合に、経路を不明とする
*/

CREATE OR REPLACE TABLE `tryt-bigquery-pj.marketing_edit_v2.03_04_const_contract_processed` AS 

WITH
    contract_amount AS ( 
        SELECT
            t1.* EXCEPT(record_date)
            , '施工管理' AS occupation 
            , t1.record_date
            , CASE 
                WHEN DATE_ADD(DATE_TRUNC(t2.calendar_date , MONTH) , INTERVAL - 1 MONTH) IS NULL THEN t1.record_month_before_edit --翌月2営業日のみ抜粋したテーブルに当該計上日が存在しないならば、通常の計上書類チェック月 を出力する(ex.「10/15 計上」は 翌月2営業日のみ抜粋したテーブルに存在しないので、「2024年10月」 を出力)
                ELSE DATE_ADD(DATE_TRUNC(t2.calendar_date , MONTH) , INTERVAL - 1 MONTH)            -- 翌月2営業日のみ抜粋したテーブルに当該計上日が存在するならば、【計上日を丸めた月 -1】月を出力する(ex.「10/2 計上」は 翌月2営業日のみ抜粋したテーブルに存在するので、「2024年9月」を出力 )
            END AS record_month                                                                     -- ★★★★★営業日を判定するテーブルの中で2営業日以内の日付と紐づくrecord_date（計上日）は前月計上とする = 翌月1営/2営 における計上は前月分として補正する ex) 「10/2 計上」のレコードは9月分として集計される ★★★★★
        FROM `tryt-bigquery-pj.marketing_edit_v2.03_02_const_contract_raw` t1
        LEFT JOIN `tryt-bigquery-pj.marketing_edit_v2.00_01_02_workday_for_invoice` AS t2           -- ★★★営業日判定用マスタにおいて、翌月2営業日のみのみ抜粋したテーブル(翌月2営業日までの計上承認は前月の計上として処理をするルールが存在) https://docs.google.com/spreadsheets/d/1tVy_iOad8mgyKCzG3XVbcKyyphGx0dosTHpRBb9DR80/edit?gid=1687421902#gid=1687421902
            ON t1.record_date = t2.calendar_date
        WHERE t1.record_date <= DATE('2025-04-02') 
        UNION ALL

        SELECT
            t1.* EXCEPT(record_date)
            , '施工管理' AS occupation
            , CASE
                WHEN t1.record_date BETWEEN DATE('2025-04-03') AND DATE('2025-04-30') THEN t1.record_date
                ELSE t2.accounting_receipt_date__c 
            END AS record_date                                         
            , DATE_TRUNC(t2.sales_date, MONTH) AS record_month
        FROM `tryt-bigquery-pj.marketing_edit_v2.03_02_const_contract_raw` t1
        LEFT JOIN `tryt-bigquery-pj.production_tryt.master_sales_date` AS t2                        -- 【重要】営業日マスタ(営業本部にて管理しているのでこちらを正として運用すること) https://docs.google.com/spreadsheets/d/1se4E_tSOTM50Td9WsTmpYhpLd3_CIYQMjYT36uupTVc/edit?gid=559861048#gid=559861048
            ON CASE
                WHEN t1.record_date BETWEEN DATE('2025-04-03') AND DATE('2025-04-30') THEN t1.record_date = t2.documents_check_date__c  
                ELSE t1.record_date = t2.accounting_receipt_date__c  
            END
        WHERE t1.record_date >= DATE('2025-04-03')                                               
    ),

    record_raw_history AS (
        SELECT 
            cd__c
            , ARRAY_AGG(STRUCT(contact_date, contact_month1, entry_route, judge_entry_route, step1) ORDER BY contact_date DESC) AS arr_history
        FROM `tryt-bigquery-pj.marketing_edit_v2.01_05_02_record_raw`
        WHERE cd__c IS NOT NULL
        GROUP BY cd__c
    ),

    normal_classified AS ( -- 広告・SEO・通常CRM 経由のレコード
        SELECT
            t1.cd__c
            , t1.occupation
            , t1.record_date
            , t1.owner_id
            , t1.total_amount
            , t1.f_amount__c
            , t1.f_6_amount__c
            , t1.f_12_amount__c
            , t1.f_24_amount__c
            , t2.contact_date
            , t2.contact_month1
            , t2.entry_route
            , t2.judge_entry_route
            , CASE 
                WHEN DATE_ADD(t2.contact_date , INTERVAL 3 MONTH) > t1.record_date THEN 1  --登録日から3ヵ月以内に計上されていればMK経由と判定
                ELSE 0 
            END AS marketing_route 
        FROM contract_amount AS t1
        LEFT JOIN record_raw_history AS t_hist
            ON t1.cd__c = t_hist.cd__c
        CROSS JOIN UNNEST(ARRAY(
            SELECT AS STRUCT h.contact_date, h.contact_month1, h.entry_route, h.judge_entry_route
            FROM UNNEST(t_hist.arr_history) AS h
            WHERE h.contact_date <= t1.record_date
                AND h.entry_route <> 'NU'
                AND NOT (h.entry_route = 'CRM' AND h.judge_entry_route LIKE '%再登録%' AND h.judge_entry_route NOT LIKE '%LINE%' AND h.judge_entry_route NOT LIKE '%友人紹介%')
            ORDER BY h.contact_date DESC
            LIMIT 1
        )) AS t2
        QUALIFY ROW_NUMBER() OVER(PARTITION BY t1.cd__c ORDER BY t2.contact_date DESC) = 1
    ),

    crm_classified AS ( -- CRM再登録 経由のレコード
        SELECT
            t1.cd__c
            , t1.occupation
            , t1.record_date
            , t1.owner_id
            , t1.total_amount
            , t1.f_amount__c
            , t1.f_6_amount__c
            , t1.f_12_amount__c
            , t1.f_24_amount__c
            , t2.contact_date
            , t2.contact_month1
            , t2.entry_route
            , t2.judge_entry_route
            , CASE 
                WHEN t2.contact_date + 7 >= t2.step1 THEN 1                               -- CRM再登録後7日以内にヒアリング転換の場合
                WHEN DATE_ADD(t2.contact_date , INTERVAL 3 MONTH) > t1.record_date THEN 2 -- 成約から遡り3カ月以内にCRM再登録のレコードがある場合
                ELSE 0 
            END AS crm_marketing_route
        FROM contract_amount AS t1
        LEFT JOIN record_raw_history AS t_hist
            ON t1.cd__c = t_hist.cd__c
        CROSS JOIN UNNEST(ARRAY(
            SELECT AS STRUCT h.contact_date, h.contact_month1, h.entry_route, h.judge_entry_route, h.step1
            FROM UNNEST(t_hist.arr_history) AS h
            WHERE h.contact_date <= t1.record_date
                AND h.entry_route = 'CRM'
                AND h.judge_entry_route LIKE '%再登録%'
                AND h.judge_entry_route NOT LIKE '%LINE%' 
                AND h.judge_entry_route NOT LIKE '%友人紹介%'
            ORDER BY h.contact_date DESC
            LIMIT 1
        )) AS t2
        QUALIFY ROW_NUMBER() OVER(PARTITION BY t1.cd__c ORDER BY t2.contact_date DESC) = 1
    ),

    route_judged AS ( -- ★★★成約情報に対して求職者情報を突合し、どの経路により成約に至ったかを判定する
        SELECT
            t1.id_invoice
            , t1.cd__c
            , t2.marketing_route
            , t1.occupation
            , CAST(NULL AS STRING) AS branch                                -- 20250612追加: 01_09_03 への追加用
            , t1.owner_id
            , t1.total_amount
            , t1.f_amount__c
            , t1.f_6_amount__c
            , t1.f_12_amount__c
            , t1.f_24_amount__c
            , t1.record_date
            , t1.record_month
            , CASE 
                WHEN t2.marketing_route = 1 THEN t2.contact_date            --広告・SEO・通常CRMのレコード
                WHEN t3.crm_marketing_route = 1 THEN t3.contact_date        --CRM再登録のレコード
                WHEN t3.crm_marketing_route = 2 THEN t3.contact_date        --CRM再登録のレコード
                ELSE GREATEST(IFNULL(t2.contact_date, DATE('1000-01-01')), IFNULL(t3.contact_date, DATE('1000-01-01'))) 
            END AS contact_date
            , CASE 
                WHEN t2.marketing_route = 1 THEN t2.contact_month1          --広告・SEO・通常CRMのレコード
                WHEN t3.crm_marketing_route = 1 THEN t3.contact_month1      --CRM再登録のレコード
                WHEN t3.crm_marketing_route = 2 THEN t3.contact_month1      --CRM再登録のレコード
                ELSE GREATEST(IFNULL(t2.contact_month1, DATE('1000-01-01')), IFNULL(t3.contact_month1, DATE('1000-01-01'))) 
            END AS contact_month
            , CASE 
                WHEN t2.marketing_route = 1 THEN t2.entry_route             --広告・SEO・通常CRMのレコード
                ELSE 'CRM' 
            END AS status --★★★★★出口における経路分類に活用している(接触日から3ヵ月以内に計上されていればMK経由と判定し1のフラグが立つ、MK経由で無いと判定されたら"CRM"とする)★★★★★
            , CASE 
                WHEN t2.marketing_route = 1 THEN t2.judge_entry_route       --広告・SEO・通常CRMのレコード
                WHEN t3.crm_marketing_route = 1 THEN t3.judge_entry_route   --CRM再登録のレコード
                WHEN t3.crm_marketing_route = 2 THEN t3.judge_entry_route   --CRM再登録のレコード
                ELSE '不明' 
            END AS judge_entry_route_fixed --★★出口における経路分類に活用している
            , CASE 
                WHEN t2.marketing_route = 1 THEN t2.entry_route             --広告・SEO・通常CRMのレコード
                ELSE NULL 
            END AS entry_route
            , CASE 
                WHEN t2.marketing_route = 1 THEN t2.judge_entry_route       --広告・SEO・通常CRMのレコード
                ELSE NULL 
            END AS judge_entry_route
        FROM contract_amount t1
        LEFT JOIN normal_classified AS t2   --広告・SEO・通常CRMのレコード
            ON t1.cd__c = t2.cd__c
        LEFT JOIN crm_classified AS t3      --CRM再登録のレコード
            ON t1.cd__c = t3.cd__c
    )

--最終集計
SELECT
    *
FROM route_judged;
-- marketing_edit_v2.03_04_const_contract_processed



-- marketing_edit_v2.01_06_01_before_daily_share
    -- 更新日：2026/04/07
    -- 作業者：細江
    -- 更新内容：進捗率コメント修正

/*
■実行内容
入口での集計対象となるレコードについて、各ステップでの転換実績を整形 (各項目は2021年頃のロジックが作成された当初(面接設定数がKPIだった)の名称を踏襲している形) 
(contact_dateがNULLの場合を除き、cd__c と contact_date と judge_entry_route により一意)
※各項目は、代理店向けCSVファイルの引用元となる後続のtryt-bigquery-pj.marketing_output_v2.01_digital_marketing_dailyにおいて必要であるため、これ以上のカラム削除は出来ません (250202 KI追記)
*/

CREATE OR REPLACE TABLE `tryt-bigquery-pj.marketing_edit_v2.01_06_01_before_daily_share` PARTITION BY contact_date CLUSTER BY entry_route, judge_entry_route AS 
WITH 
    lead_time AS ( -- 接触月毎に各ステップのリードタイムを明示したマスタを突合(2020年頃にリヴァンプ社がエクセル上で作成したマスタをスプレッドシートに転記する形での運用となっている)
        SELECT
            t1.*
            , t2.count_send_date_1      -- ステップ1のリードタイム (職種別に登録月から30営業日程度で設定されている)
            , t2.count_send_date_2      -- ステップ2のリードタイム (職種別に登録月から32営業日程度で設定されている)
            , t2.count_send_date_3      -- ステップ3のリードタイム (職種別に登録月から35営業日で設定されている)
            , t2.count_send_date_4      -- ステップ4のリードタイム (職種別に登録月から40営業日で設定されている)
        FROM `tryt-bigquery-pj.marketing_edit_v2.01_05_02_record_raw` AS t1
        LEFT JOIN `tryt-bigquery-pj.production_tryt.master_lead_time`  AS t2 -- リードタイムのマスタ https://docs.google.com/spreadsheets/d/1tVy_iOad8mgyKCzG3XVbcKyyphGx0dosTHpRBb9DR80/edit?gid=984875189#gid=984875189  
            ON t1.occupation = t2.occupation
                AND t1.contact_month1 = t2.entry_date  -- 求職者に対して接触月・職種ごとのリードタイムを結び付け
        ),

    step_count AS ( -- ステップごとにKPI実績を集計
        SELECT
            * EXCEPT(cvv , n_cvv)
            , CASE 
                WHEN contact_date <= cutoff_date1 AND entrance_flag = 1 THEN cvv            -- ★★★ entrance_flag = 入口フラグ(接触数カウントから集計対象外の求職者を除外するために活用)
                ELSE 0 
            END AS cvv                      -- CVV
            , CASE 
                WHEN contact_date <= cutoff_date1 AND entrance_flag = 1 THEN n_cvv          -- ★★★ entrance_flag = 入口フラグ(接触数カウントから集計対象外の求職者を除外するために活用)
                ELSE 0 
            END AS n_cvv                    -- 次回使用予定CVV
            , CASE 
                WHEN contact_date <= cutoff_date1 AND entrance_flag = 1 THEN 1              -- ★★★ entrance_flag = 入口フラグ(接触数カウントから集計対象外の求職者を除外するために活用)
                ELSE 0 
            END AS contact_count1           -- 接触数
            , CASE 
                WHEN contact_date <= cutoff_date1 AND experience = 1 THEN 1                 -- experience=施工管理経験者
                ELSE 0 
            END AS experience_count1        -- 経験者数
            , CASE 
                WHEN contact_date <= cutoff_date1 AND young_experience = 1 THEN 1           -- young_experience=若年層経験者
                ELSE 0 
            END AS young_experience_count1  -- 若年層経験者数
            , CASE 
                WHEN step0_5 BETWEEN contact_date AND LEAST(count_send_date_1 , cutoff_date1) AND entrance_flag = 1 THEN 1 -- ★★★ entrance_flag = 入口フラグ(接触数カウントから集計対象外の求職者を除外するために活用)
                ELSE 0 
            END AS step0_5_count_for_rate1  -- 数0.5
            , CASE 
                WHEN step1 BETWEEN contact_date AND LEAST(count_send_date_1 , cutoff_date1) THEN 1 
                ELSE 0 
            END AS step1_count_for_rate1    -- 数1
            , CASE 
                WHEN step2 BETWEEN contact_date AND LEAST(count_send_date_2 , cutoff_date1) THEN 1 
                ELSE 0 
            END AS step2_count_for_rate1    -- 数2
            , CASE 
                WHEN step3 BETWEEN contact_date AND LEAST(count_send_date_3 , cutoff_date1) THEN 1 
                ELSE 0 
            END AS step3_count_for_rate1    -- 数3
            , CASE 
                WHEN step4 BETWEEN contact_date AND LEAST(count_send_date_4 , cutoff_date1) THEN 1 
                ELSE 0 
            END AS step4_count_for_rate1    -- 数4
            , CASE 
                WHEN step5 BETWEEN contact_date AND LEAST(DATE_ADD(contact_date, INTERVAL 3 MONTH) - 1 , cutoff_date1) THEN 1 
                ELSE 0 
            END AS step5_count_for_rate1    -- 数5
        FROM lead_time
       ),

    workday_calc AS ( -- 営業日を集計
        SELECT
            calendar_date
            , workday_calculation_thismonth_1
            , workday_calculation_lastmonth_1
            , workday_flg
            , SUM(workday_flg) OVER (ORDER BY calendar_date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumulative_workdays -- 累積営業日  
        FROM `tryt-bigquery-pj.production_tryt.master_workday` -- 営業日マスタ https://docs.google.com/spreadsheets/d/1se4E_tSOTM50Td9WsTmpYhpLd3_CIYQMjYT36uupTVc/edit?gid=1687421902#gid=1687421902
        WHERE calendar_date <= CURRENT_DATE('Asia/Tokyo')
        ),

    workday AS ( -- 各アクションにおける営業日情報を突合
        SELECT
            t1.*
            , c00.workday_calculation_thismonth_1                    -- 当月起算営業日
            , c00.workday_calculation_lastmonth_1                    -- 前月起算営業日
            , CASE 
                WHEN t1.contact_month1 = DATE_TRUNC(t1.cutoff_date1 , MONTH) THEN c00.workday_calculation_thismonth_1 
                WHEN DATE_ADD(t1.contact_month1, INTERVAL 1 MONTH) = DATE_TRUNC(t1.cutoff_date1 , MONTH) THEN c00.workday_calculation_lastmonth_1
                ELSE NULL 
            END AS cutoff_workday1 -- 〆営業日（昨日〆）
            , c01.workday_calculation_thismonth_1 AS contact_workday -- 接触営業日

            -- 以下の営業日の集計において、集計起点日となる「接触月」の日付が営業日ならば、+1 する必要があるので注意 (251030 ロジック変更)
            , CASE WHEN c02.workday_flg = 1 THEN c0_5.cumulative_workdays - c02.cumulative_workdays + 1 ELSE c0_5.cumulative_workdays - c02.cumulative_workdays END AS step0_5_workday -- step0.5営業日 (接触月から起算してstep0.5が何営業日目に発生したかを集計している)
            , CASE WHEN c02.workday_flg = 1 THEN c1.cumulative_workdays - c02.cumulative_workdays + 1 ELSE c1.cumulative_workdays - c02.cumulative_workdays END AS step1_workday       -- step1営業日 (接触月から起算してstep1が何営業日目に発生したかを集計している)
            , CASE WHEN c02.workday_flg = 1 THEN c2.cumulative_workdays - c02.cumulative_workdays + 1 ELSE c2.cumulative_workdays - c02.cumulative_workdays END AS step2_workday       -- step2営業日 (接触月から起算してstep2が何営業日目に発生したかを集計している)
            , CASE WHEN c02.workday_flg = 1 THEN c3.cumulative_workdays - c02.cumulative_workdays + 1 ELSE c3.cumulative_workdays - c02.cumulative_workdays END AS step3_workday       -- step3営業日 (接触月から起算してstep3が何営業日目に発生したかを集計している)
            , CASE WHEN c02.workday_flg = 1 THEN c4.cumulative_workdays - c02.cumulative_workdays + 1 ELSE c4.cumulative_workdays - c02.cumulative_workdays END AS step4_workday       -- step4営業日 (接触月から起算してstep4が何営業日目に発生したかを集計している)
            , CASE WHEN c02.workday_flg = 1 THEN c5.cumulative_workdays - c02.cumulative_workdays + 1 ELSE c5.cumulative_workdays - c02.cumulative_workdays END AS step5_workday       -- step5営業日 (接触月から起算してstep5が何営業日目に発生したかを集計している)
            , c7.workday_calculation_thismonth_1 AS last_workday
        FROM step_count AS t1
        LEFT JOIN workday_calc c00
            ON t1.cutoff_date1 = c00.calendar_date
        LEFT JOIN workday_calc c01
            ON t1.contact_date = c01.calendar_date
        LEFT JOIN workday_calc c02
            ON t1.contact_month1 = c02.calendar_date

        LEFT JOIN workday_calc c0_5
            ON t1.step0_5 = c0_5.calendar_date
            AND t1.entrance_flag = 1                     -- entrance_flag = 入口フラグ(接触数カウントから除外するために活用)、通電は接触(ステップ0.5)のある場合にのみ紐づける
        LEFT JOIN workday_calc c1
            ON t1.step1 = c1.calendar_date
        LEFT JOIN workday_calc c2
            ON t1.step2 = c2.calendar_date
        LEFT JOIN workday_calc c3
            ON t1.step3 = c3.calendar_date
        LEFT JOIN workday_calc c4
            ON t1.step4 = c4.calendar_date
        LEFT JOIN workday_calc c5
            ON t1.step5 = c5.calendar_date
        LEFT JOIN workday_calc c6
            ON t1.record_date = c6.calendar_date
        LEFT JOIN workday_calc c7
            ON LAST_DAY(t1.contact_month1) = c7.calendar_date   
      ),

    same_workday AS ( -- 各月における同営業日時点での集計を行うために整形
        SELECT
            *
            , CASE 
                WHEN contact_count1 = 1 AND contact_workday <= workday_calculation_thismonth_1 THEN 1 
                ELSE 0 
            END AS contact_count_same_workday_comparison1                                   -- （当月同営時点）接触数
            , contact_count1 AS contact_count_same_workday_comparison2                      -- （前月同営時点）接触数
            , CASE 
                WHEN experience_count1 = 1 AND contact_workday <= workday_calculation_thismonth_1 THEN 1 
                ELSE 0 
            END AS experience_count_same_workday_comparison1                                -- （当月同営時点）経験者数
            , experience_count1 AS experience_count_same_workday_comparison2                -- （前月同営時点）経験者数
            , CASE 
                WHEN young_experience_count1 = 1 AND contact_workday <= workday_calculation_thismonth_1 THEN 1 
                ELSE 0 
            END AS young_experience_count_same_workday_comparison1                          -- （当月同営時点）若年層経験者数
            , young_experience_count1 AS young_experience_count_same_workday_comparison2    -- （前月同営時点）若年層経験者数
            , CASE 
                WHEN step0_5_count_for_rate1 = 1 AND step0_5_workday <= workday_calculation_thismonth_1 THEN 1 
                ELSE 0 
            END AS step0_5_count_same_workday_comparison1                                   -- （当月同営時点）数0.5
            , CASE 
                WHEN step0_5_count_for_rate1 = 1 AND step0_5_workday <= workday_calculation_lastmonth_1 THEN 1 
                ELSE 0 
            END AS step0_5_count_same_workday_comparison2                                   -- （前月同営時点）数0.5
            , CASE 
                WHEN step1_count_for_rate1 = 1 AND step1_workday <= workday_calculation_thismonth_1 THEN 1 
                ELSE 0 
            END AS step1_count_same_workday_comparison1                                     -- （当月同営時点）数1
            , CASE 
                WHEN step1_count_for_rate1 = 1 AND step1_workday <= workday_calculation_lastmonth_1 THEN 1 
                ELSE 0 
            END AS step1_count_same_workday_comparison2                                     -- （前月同営時点）数1
            , CASE 
                WHEN step2_count_for_rate1 = 1 AND step2_workday <= workday_calculation_thismonth_1 THEN 1 
                ELSE 0 
            END AS step2_count_same_workday_comparison1                                     -- （当月同営時点）数2
            , CASE 
                WHEN step2_count_for_rate1 = 1 AND step2_workday <= workday_calculation_lastmonth_1 THEN 1 
                ELSE 0 
            END AS step2_count_same_workday_comparison2                                     -- （前月同営時点）数2
            , CASE 
                WHEN step3_count_for_rate1 = 1 AND step3_workday <= workday_calculation_thismonth_1 THEN 1 
                ELSE 0 
            END AS step3_count_same_workday_comparison1                                     -- （当月同営時点）数3
            , CASE 
                WHEN step3_count_for_rate1 = 1 AND step3_workday <= workday_calculation_lastmonth_1 THEN 1 
                ELSE 0 
            END AS step3_count_same_workday_comparison2                                     -- （前月同営時点）数3
            , CASE 
                WHEN step4_count_for_rate1 = 1 AND step4_workday <= workday_calculation_thismonth_1 THEN 1 
                ELSE 0 
            END AS step4_count_same_workday_comparison1                                     -- （当月同営時点）数4
            , CASE 
                WHEN step4_count_for_rate1 = 1 AND step4_workday <= workday_calculation_lastmonth_1 THEN 1 
                ELSE 0 
            END AS step4_count_same_workday_comparison2                                     -- （前月同営時点）数4
            , CASE 
                WHEN step5_count_for_rate1 = 1 AND step5_workday <= workday_calculation_thismonth_1 THEN 1 
                ELSE 0 
            END AS step5_count_same_workday_comparison1                                     -- （当月同営時点）数5
            , CASE 
                WHEN step5_count_for_rate1 = 1 AND step5_workday <= workday_calculation_lastmonth_1 THEN 1 
                ELSE 0 
            END AS step5_count_same_workday_comparison2                                     -- （前月同営時点）数5
        FROM workday
      ),

    expected_count AS ( -- 広告代理店へ日次で提供しているcsvデータ向けに、集計末日に至っていない月において、集計末日時点における着地見込みを算出
        SELECT
            t1.*
            , CASE 
                WHEN DATE_TRUNC(t1.cutoff_date1 , MONTH) = t1.contact_month1 THEN t1.contact_count1 * EXTRACT(DAY FROM LAST_DAY(t1.cutoff_date1)) / EXTRACT(DAY FROM t1.cutoff_date1)
                ELSE t1.contact_count1 
            END AS expected_contact_count1                                                  -- 着地接触数
            , CASE 
                WHEN DATE_TRUNC(t1.cutoff_date1 , MONTH) = t1.contact_month1 THEN t1.experience_count1 * EXTRACT(DAY FROM LAST_DAY(t1.cutoff_date1)) / EXTRACT(DAY FROM t1.cutoff_date1)
                ELSE t1.experience_count1 
            END AS expected_experience_count1                                               -- 着地経験者数
            , CASE 
                WHEN DATE_TRUNC(t1.cutoff_date1 , MONTH) = t1.contact_month1 THEN t1.young_experience_count1 * EXTRACT(DAY FROM LAST_DAY(t1.cutoff_date1)) / EXTRACT(DAY FROM t1.cutoff_date1)
                ELSE t1.young_experience_count1 
            END AS expected_young_experience_count1                                         -- 着地若年層経験者数
            , CASE 
                WHEN entry_route = '広告'THEN 
                    CASE 
                        WHEN DATE_TRUNC(t1.cutoff_date1 , MONTH) = t1.contact_month1 THEN           -- 〆日(=昨日)を月で丸めた値 = 接触日を月で丸めた値 ならば
                            CASE 
                                WHEN t2.advertising_progress_rate_1_1 IS NULL OR t2.advertising_progress_rate_1_1 = 0 THEN t1.step1_count_for_rate1 
                                ELSE t1.step1_count_for_rate1 / t2.advertising_progress_rate_1_1    -- 〆日(=昨日)における「数1」÷ 〆日の月における広告経由の進捗率
                            END
                        ELSE CASE                                                                   -- 〆日(=昨日)を月で丸めた値 ≠ 接触日を月で丸めた値 ならば 
                                WHEN t2.advertising_progress_rate_1_2 IS NULL OR t2.advertising_progress_rate_1_2 = 0 THEN t1.step1_count_for_rate1 
                                ELSE t1.step1_count_for_rate1 / t2.advertising_progress_rate_1_2    -- 〆日(=昨日)における「数1」÷ 〆日の【前月】における広告経由の進捗率
                                /* 例えばN月の30営業日における進捗率を求める場合、30営業日は実質N+1月の20日頃となり、その時点における進捗率は前月起算のものを参照する必要があるため、このような分岐が必要になる */ 
                            END 
                    END
                WHEN entry_route = 'CRM' THEN 
                    CASE 
                        WHEN DATE_TRUNC(t1.cutoff_date1 , MONTH) = t1.contact_month1 THEN 
                            CASE 
                                WHEN t2.crm_progress_rate_1_1 IS NULL OR t2.crm_progress_rate_1_1 = 0 THEN t1.step1_count_for_rate1 
                                ELSE t1.step1_count_for_rate1 / t2.crm_progress_rate_1_1 
                            END
                        ELSE CASE 
                                WHEN t2.crm_progress_rate_1_2 IS NULL OR t2.crm_progress_rate_1_2 = 0 THEN t1.step1_count_for_rate1 
                                ELSE t1.step1_count_for_rate1 / t2.crm_progress_rate_1_2 
                            END 
                    END 
                WHEN entry_route = 'SEO' THEN 
                    CASE 
                        WHEN DATE_TRUNC(t1.cutoff_date1 , MONTH) = t1.contact_month1 THEN 
                            CASE 
                                WHEN t2.seo_progress_rate_1_1 IS NULL OR t2.seo_progress_rate_1_1 = 0 THEN t1.step1_count_for_rate1 
                                ELSE t1.step1_count_for_rate1 / t2.seo_progress_rate_1_1 
                            END
                        ELSE CASE 
                                WHEN t2.seo_progress_rate_1_2 IS NULL OR t2.seo_progress_rate_1_2 = 0 THEN t1.step1_count_for_rate1 
                                ELSE t1.step1_count_for_rate1 / t2.seo_progress_rate_1_2 
                            END 
                    END
                ELSE t1.step1_count_for_rate1 
            END AS expected_step1_count1                                                    -- 着地数1
            , CASE 
                WHEN entry_route = '広告' THEN 
                    CASE 
                        WHEN DATE_TRUNC(t1.cutoff_date1 , MONTH)  = t1.contact_month1 THEN 
                            CASE 
                                WHEN t2.advertising_progress_rate_2_1 IS NULL OR t2.advertising_progress_rate_2_1 = 0 THEN t1.step2_count_for_rate1 
                                ELSE t1.step2_count_for_rate1 / t2.advertising_progress_rate_2_1 
                            END
                        ELSE CASE 
                                WHEN t2.advertising_progress_rate_2_2 IS NULL OR t2.advertising_progress_rate_2_2 = 0 THEN t1.step2_count_for_rate1 
                                ELSE t1.step2_count_for_rate1 / t2.advertising_progress_rate_2_2 
                            END 
                    END
                WHEN entry_route = 'CRM' THEN 
                    CASE 
                        WHEN DATE_TRUNC(t1.cutoff_date1 , MONTH) = t1.contact_month1 THEN 
                            CASE 
                                WHEN t2.crm_progress_rate_2_1 IS NULL OR t2.crm_progress_rate_2_1 = 0 THEN t1.step2_count_for_rate1 
                                ELSE t1.step2_count_for_rate1 / t2.crm_progress_rate_2_1 
                            END
                        ELSE CASE 
                                WHEN t2.crm_progress_rate_2_2 IS NULL OR t2.crm_progress_rate_2_2 = 0 THEN t1.step2_count_for_rate1 
                                ELSE t1.step2_count_for_rate1 / t2.crm_progress_rate_2_2 
                            END 
                    END
                WHEN entry_route = 'SEO' THEN 
                    CASE 
                        WHEN DATE_TRUNC(t1.cutoff_date1 , MONTH) = t1.contact_month1 THEN 
                            CASE 
                                WHEN t2.seo_progress_rate_2_1 IS NULL OR t2.seo_progress_rate_2_1 = 0 THEN t1.step2_count_for_rate1
                                ELSE t1.step2_count_for_rate1 / t2.seo_progress_rate_2_1 
                            END
                        ELSE CASE 
                                WHEN t2.seo_progress_rate_2_2 IS NULL OR t2.seo_progress_rate_2_2 = 0 THEN t1.step2_count_for_rate1 
                                ELSE t1.step2_count_for_rate1 / t2.seo_progress_rate_2_2 
                            END 
                    END 
                ELSE t1.step2_count_for_rate1 
            END AS expected_step2_count1                                                    -- 着地数2
            , CASE 
                WHEN entry_route = '広告' THEN 
                    CASE 
                        WHEN DATE_TRUNC(t1.cutoff_date1 , MONTH) = t1.contact_month1 THEN 
                            CASE 
                                WHEN t2.advertising_progress_rate_3_1 IS NULL OR t2.advertising_progress_rate_3_1 = 0 THEN t1.step3_count_for_rate1 
                                ELSE t1.step3_count_for_rate1 / t2.advertising_progress_rate_3_1 
                            END
                        ELSE CASE 
                                WHEN t2.advertising_progress_rate_3_2 IS NULL OR t2.advertising_progress_rate_3_2 = 0 THEN t1.step3_count_for_rate1 
                                ELSE t1.step3_count_for_rate1 / t2.advertising_progress_rate_3_2 
                            END 
                    END
                WHEN entry_route = 'CRM' THEN 
                    CASE 
                        WHEN DATE_TRUNC(t1.cutoff_date1 , MONTH) = t1.contact_month1 THEN 
                            CASE 
                                WHEN t2.crm_progress_rate_3_1 IS NULL OR t2.crm_progress_rate_3_1 = 0 THEN t1.step3_count_for_rate1 
                                ELSE t1.step3_count_for_rate1 / t2.crm_progress_rate_3_1 
                            END
                        ELSE CASE 
                                WHEN t2.crm_progress_rate_3_2 IS NULL OR t2.crm_progress_rate_3_2 = 0 THEN t1.step3_count_for_rate1
                                ELSE t1.step3_count_for_rate1 / t2.crm_progress_rate_3_2 
                            END 
                    END
                WHEN entry_route = 'SEO' THEN 
                    CASE 
                        WHEN DATE_TRUNC(t1.cutoff_date1 , MONTH) = t1.contact_month1 THEN 
                            CASE 
                                WHEN t2.seo_progress_rate_3_1 IS NULL OR t2.seo_progress_rate_3_1 = 0 THEN t1.step3_count_for_rate1 
                                ELSE t1.step3_count_for_rate1 / t2.seo_progress_rate_3_1 
                            END
                        ELSE CASE 
                                WHEN t2.seo_progress_rate_3_2 IS NULL OR t2.seo_progress_rate_3_2 = 0 THEN t1.step3_count_for_rate1 
                                ELSE t1.step3_count_for_rate1 / t2.seo_progress_rate_3_2 
                            END 
                    END
                ELSE t1.step3_count_for_rate1 
            END AS expected_step3_count1                                                    -- 着地数3
            , CASE 
                WHEN entry_route = '広告' THEN 
                    CASE 
                        WHEN DATE_TRUNC(t1.cutoff_date1 , MONTH) = t1.contact_month1 THEN 
                            CASE 
                                WHEN t2.advertising_progress_rate_4_1 IS NULL OR t2.advertising_progress_rate_4_1 = 0 THEN t1.step4_count_for_rate1 
                                ELSE t1.step4_count_for_rate1 / t2.advertising_progress_rate_4_1 
                            END
                        ELSE CASE 
                                WHEN t2.advertising_progress_rate_4_2 IS NULL OR t2.advertising_progress_rate_4_2 = 0 THEN t1.step4_count_for_rate1 
                                ELSE t1.step4_count_for_rate1 / t2.advertising_progress_rate_4_2 
                            END 
                    END
                WHEN entry_route = 'CRM' THEN 
                    CASE 
                        WHEN DATE_TRUNC(t1.cutoff_date1 , MONTH) = t1.contact_month1 THEN 
                            CASE 
                                WHEN t2.crm_progress_rate_4_1 IS NULL OR t2.crm_progress_rate_4_1 = 0 THEN t1.step4_count_for_rate1 
                                ELSE t1.step4_count_for_rate1 / t2.crm_progress_rate_4_1 
                            END
                        ELSE CASE 
                                WHEN t2.crm_progress_rate_4_2 IS NULL OR t2.crm_progress_rate_4_2 = 0 THEN t1.step4_count_for_rate1 
                                ELSE t1.step4_count_for_rate1 / t2.crm_progress_rate_4_2 
                            END 
                    END
                WHEN entry_route = 'SEO' THEN 
                    CASE 
                        WHEN DATE_TRUNC(t1.cutoff_date1 , MONTH) = t1.contact_month1 THEN 
                            CASE 
                                WHEN t2.seo_progress_rate_4_1 IS NULL OR t2.seo_progress_rate_4_1 = 0 THEN t1.step4_count_for_rate1 
                                ELSE t1.step4_count_for_rate1 / t2.seo_progress_rate_4_1 
                            END
                        ELSE CASE 
                                WHEN t2.seo_progress_rate_4_2 IS NULL OR t2.seo_progress_rate_4_2 = 0 THEN t1.step4_count_for_rate1 
                                ELSE t1.step4_count_for_rate1 / t2.seo_progress_rate_4_2 
                            END 
                    END
                ELSE t1.step4_count_for_rate1 
            END AS expected_step4_count1                                                    -- 着地数4
        FROM same_workday AS t1
        LEFT JOIN `tryt-bigquery-pj.production_tryt.master_progress_rate` AS t2             -- 進捗率マスタ
            ON t1.cutoff_workday1 = t2.workday
                AND t1.occupation = t2.occupation
      ),

    expected_count_info_added AS ( -- その他の実績項目を追加
        SELECT
            *
            , CASE 
                WHEN occupation LIKE '%カレッジ%' OR occupation LIKE '%派遣%' OR occupation LIKE '%紹介%' THEN 0 
                ELSE 1 
            END AS occupation_flg                                                           -- ★★特定の職種（カレッジ、派遣を含む職種）を除外するためのフラグ
            , CASE
                WHEN occupation IN ('介護職', '看護師', '保育士', 'POS', '技師', 'デンタル', '栄養士', '薬剤師', '調理師' ) THEN step3_count_for_rate1 
                WHEN occupation = '施工管理' THEN contact_count1
                ELSE NULL
            END AS actual_count1                                                            -- 実績 (紹介事業は面接設定数、施工は登録数)
            , CASE
                WHEN occupation IN ('介護職', '看護師', '保育士', 'POS', '技師', 'デンタル', '栄養士', '薬剤師', '調理師' ) THEN expected_step3_count1 
                WHEN occupation = '施工管理' THEN expected_contact_count1
                ELSE NULL
            END AS expected_actual_count1                                                   -- 見込 (紹介事業は面接設定数、施工は登録数)   
            , CASE
                WHEN occupation IN ('介護職', '看護師', '保育士', 'POS', '技師', 'デンタル', '栄養士', '薬剤師', '調理師' ) THEN step3_count_same_workday_comparison1  
                WHEN occupation = '施工管理' THEN contact_count_same_workday_comparison1
                ELSE NULL
            END AS actual_count_same_workday_comparison1                                    --（当月同営時点）実績 (紹介事業は面接設定数、施工は登録数) 
            , CASE
                WHEN occupation IN ('介護職', '看護師', '保育士', 'POS', '技師', 'デンタル', '栄養士', '薬剤師', '調理師' ) THEN step3_count_same_workday_comparison2  
                WHEN occupation = '施工管理' THEN contact_count_same_workday_comparison2
                ELSE NULL
            END AS actual_count_same_workday_comparison2                                    --（前月同営時点）実績 (紹介事業は面接設定数、施工は登録数)
        FROM expected_count
        WHERE entry_route IS NOT NULL
    )

--最終集計
SELECT
    *
FROM expected_count_info_added;
-- marketing_edit_v2.01_06_01_before_daily_share



-- marketing_edit_v2.01_06_02_before_daily_share
    -- 更新日：2026/07/17
    -- 作業者：細江
    -- 更新内容：タイムアウト（DEADLINE_EXCEEDED）エラーに伴うリファクタリング

/*
■実行内容
入口の求職者情報(01_06_01_before_daily_share)に対して成約情報を突合する 
(contact_dateがNULLの場合を除き、cd__c と contact_date と judge_entry_route により一意)

※各項目は、代理店向けCSVファイルの引用元となる後続のtryt-bigquery-pj.marketing_output_v2.01_digital_marketing_dailyにおいて必要であるため、これ以上のカラム削除は出来ません (250202 KI追記)
CSVファイルは右記のGoogle Cloud のバケットに出力されるがトラブル発生時はTableau Prepより出力すること https://console.cloud.google.com/storage/browser/mk_digital_marketing_daily_export;tab=objects?forceOnBucketsSortingFiltering=true&hl=JA&project=tryt-bigquery-pj&prefix=&forceOnObjectsSortingFiltering=false&inv=1&invt=AbxMIg
CSVファイル出力用マスタ：https://docs.google.com/spreadsheets/d/1C3gd5v9NoEbBcvb5j4ljDhskNK_OjcN-GLcg9m0pp_8/edit?gid=1387366478#gid=1387366478
*/

CREATE OR REPLACE TABLE `tryt-bigquery-pj.marketing_edit_v2.01_06_02_before_daily_share` AS 
WITH 
    contract_count_career AS ( -- 紹介事業における成約数
        SELECT
            cd__c
            , judge_entry_route_fixed
            , contact_date
            , COUNT(DISTINCT cd__c) AS contract_cnt -- 【注意】参照    
        FROM `tryt-bigquery-pj.marketing_edit_v2.03_03_career_contract_processed`
        WHERE gross_flg = 1
            AND contract_count = 1
        GROUP BY 1 , 2 , 3
        ),

    gross_sales_career AS ( -- 紹介事業におけるグロス売上
        SELECT
            cd__c
            , judge_entry_route_fixed
            , contact_date
            , SUM(sales_amount__c) AS sales_amount__c -- グロス売上
        FROM `tryt-bigquery-pj.marketing_edit_v2.03_03_career_contract_processed`
        WHERE gross_flg = 1
        GROUP BY 1 , 2 , 3
        ),

    net_sales_career AS ( -- 紹介事業における純契約売上
        SELECT
            cd__c
            , judge_entry_route_fixed
            , contact_date
            , SUM(sales_amount__c) AS sales_amount__c -- 純契約売上
        FROM `tryt-bigquery-pj.marketing_edit_v2.03_03_career_contract_processed`
        GROUP BY 1 , 2 , 3
        ),

    contract_count_const AS ( -- 施工管理における成約数
        SELECT
            cd__c
            , judge_entry_route_fixed
            , contact_date
            , COUNT(DISTINCT cd__c) AS contract_cnt               
        FROM `tryt-bigquery-pj.marketing_edit_v2.03_04_const_contract_processed`
        GROUP BY 1 , 2 , 3
        ),

    sales_const AS ( -- 施工管理における売上情報
        SELECT
            cd__c
            , judge_entry_route_fixed
            , contact_date
            , SUM(total_amount) AS total_amount
            , SUM(f_amount__c) AS f_amount__c
            , SUM(f_6_amount__c) AS f_6_amount__c
            , SUM(f_12_amount__c) AS f_12_amount__c
            , SUM(f_24_amount__c) AS f_24_amount__c
        FROM `tryt-bigquery-pj.marketing_edit_v2.03_04_const_contract_processed`
        GROUP BY 1 , 2 , 3
        ),

    amount AS ( -- 入口求職者情報に売上情報を突合
        SELECT
            t1.* EXCEPT(record_date , retire_date , retire_category , retire_leadtime)
            , CASE 
                WHEN DATE_ADD(t1.contact_date , INTERVAL 3 MONTH) <= t1.record_date AND (CASE WHEN t1.occupation = '施工管理' THEN t6.total_amount ELSE t3.sales_amount__c END) IS NULL THEN NULL
                ELSE t1.record_date 
            END AS record_date
            , CASE 
                WHEN DATE_ADD(t1.contact_date , INTERVAL 3 MONTH) <= t1.record_date AND (CASE WHEN t1.occupation = '施工管理' THEN t6.total_amount ELSE t3.sales_amount__c END) IS NULL THEN NULL
                ELSE t1.retire_date 
            END AS retire_date
            , CASE 
                WHEN DATE_ADD(t1.contact_date , INTERVAL 3 MONTH) <= t1.record_date AND (CASE WHEN t1.occupation = '施工管理' THEN t6.total_amount ELSE t3.sales_amount__c END) IS NULL THEN NULL
                ELSE t1.retire_category 
            END AS retire_category        -- 辞退退職情報
            , CASE 
                WHEN DATE_ADD(t1.contact_date , INTERVAL 3 MONTH) <= t1.record_date AND (CASE WHEN t1.occupation = '施工管理' THEN t6.total_amount ELSE t3.sales_amount__c END) IS NULL THEN NULL
                ELSE t1.retire_leadtime   -- 入職予定日に対して辞退/退職がどの程度離れているかを集計
            END AS retire_leadtime
            , CASE
                WHEN t1.occupation = '施工管理' THEN t5.contract_cnt 
                ELSE t2.contract_cnt
            END AS record_count_for_rate1 -- ★★入口から集計した場合の成約数 【注意】01_06_02_before_daily_share と 01_09_03_before_exit_analysis では粒度が異なり、入口と出口の月毎の成約数は一致しないので注意 
            , CASE 
                WHEN t1.occupation = '施工管理' THEN t6.total_amount 
                ELSE t3.sales_amount__c 
            END AS sales_amount__c        -- グロス売上
            , CASE 
                WHEN t1.occupation = '施工管理' THEN t6.f_amount__c 
                ELSE t4.sales_amount__c    
            END AS amount                 -- 純契約売上
            , t6.f_6_amount__c
            , t6.f_12_amount__c
            , t6.f_24_amount__c
        FROM `tryt-bigquery-pj.marketing_edit_v2.01_06_01_before_daily_share` AS t1
        LEFT JOIN contract_count_career t2       -- 紹介 成約数  
            ON t1.cd__c = t2.cd__c
                AND t1.contact_date = t2.contact_date
                AND (t1.judge_entry_route = t2.judge_entry_route_fixed OR (t1.entry_route = 'NU' AND t2.judge_entry_route_fixed = 'NU経路')) 
        LEFT JOIN gross_sales_career AS t3       -- 紹介 グロス売上 
            ON t1.cd__c = t3.cd__c
                AND t1.contact_date = t3.contact_date
                AND (t1.judge_entry_route = t3.judge_entry_route_fixed OR (t1.entry_route = 'NU' AND t3.judge_entry_route_fixed = 'NU経路')) 
        LEFT JOIN net_sales_career AS t4         -- 紹介 純契約売上
            ON t1.cd__c = t4.cd__c
                AND t1.contact_date = t4.contact_date
                AND (t1.judge_entry_route = t4.judge_entry_route_fixed OR (t1.entry_route = 'NU' AND t4.judge_entry_route_fixed = 'NU経路')) 
        LEFT JOIN contract_count_const AS t5     -- 施工管理 成約数
            ON t1.cd__c = t5.cd__c
                AND t1.contact_date = t5.contact_date
                AND (t1.judge_entry_route = t5.judge_entry_route_fixed OR (t1.entry_route = 'NU' AND t5.judge_entry_route_fixed = 'NU経路')) 
        LEFT JOIN sales_const AS t6              -- 施工管理 売上
            ON t1.cd__c = t6.cd__c
                AND t1.contact_date = t6.contact_date
                AND (t1.judge_entry_route = t6.judge_entry_route_fixed OR (t1.entry_route = 'NU' AND t6.judge_entry_route_fixed = 'NU経路')) 
        WHERE t1.contact_month1 >= target_start_date OR t1.entry_route = 'NU'
        ),

    area_no AS ( -- 支社番号を突合し、職種・拠点イレギュラー対応の補正と営業部署情報の整形を行う ☆☆☆都度対応が必要☆☆☆
        SELECT
            t1.* EXCEPT(branch , occupation , department_in_charge__c, flg)
            , CASE 
                WHEN t1.branch = '京都（デンタル）' AND t1.yuusensikakusyuukeiyou__c IN('栄養士' , '管理栄養士' , '調理師') AND t1.contact_date >= DATE('2022-12-01') THEN '京都（栄養士）' 
                WHEN t1.branch = t3.branch_text__c_before AND t1.contact_date BETWEEN DATE('2025-07-25') AND DATE('2025-07-31') THEN t3.branch_text__c_after
                ELSE t1.branch 
            END AS branch
            , CASE 
                WHEN t1.branch = '京都（デンタル）' AND t1.yuusensikakusyuukeiyou__c IN('栄養士' , '管理栄養士' , '調理師') AND t1.contact_date >= DATE('2022-12-01') THEN '栄養士' 
                WHEN t1.branch = t3.branch_text__c_before AND t1.contact_date BETWEEN DATE('2025-07-25') AND DATE('2025-07-31') THEN '保育士'
                ELSE t1.occupation 
            END AS occupation
            , t2.area_no
            , CASE 
                WHEN LEFT(t1.department_in_charge__c , INSTR(t1.department_in_charge__c,'）')) = t1.branch THEN t1.department_in_charge__c 
                ELSE NULL 
            END AS department_in_charge__c
        FROM amount AS t1
        LEFT JOIN `tryt-bigquery-pj.production_tryt.master_branch` AS t2 -- 支社マスタ https://docs.google.com/spreadsheets/d/1tVy_iOad8mgyKCzG3XVbcKyyphGx0dosTHpRBb9DR80/edit?gid=1094227535#gid=1094227535
            ON t1.area = t2.area
                AND t2.occupation = '介護職' -- レコードが重複しないように任意の値で制限する
        LEFT JOIN `tryt-bigquery-pj.marketing_edit_v2.ca_list_to_be_corrected_20250806` AS t3 -- 2025/7/25 ~ 2025/7/31 における担当拠点のスワップの補正用マスタ
            ON t1.owner_id = t3.owner_id
        )

--最終集計
SELECT
    *
FROM area_no;
-- marketing_edit_v2.01_06_02_before_daily_share



-- marketing_edit_v2.01_07_before_entrance_analysis
    -- 更新日：2026/05/18
    -- 作業者：細江・山本
    -- 更新内容：想定ステップ3転換確率・想定売上価値の v2 を追加

/*
■実行内容
入口に関する集計は主に本テーブルがデータマートとなり展開されるため、BI向けの整形を行う(デジタルマーケティング課向けの「日次ローデータ」に出力するための項目は本テーブルの前の01_06_02_before_daily_shareにおいて加工すること)
(contact_dateがNULLの場合を除き、cd__c と contact_date と judge_entry_route により一意)
*/

CREATE OR REPLACE TABLE `tryt-bigquery-pj.marketing_edit_v2.01_07_before_entrance_analysis` PARTITION BY contact_month CLUSTER BY occupation, entry_route AS -- 【重要】後続の"各種転換率(入口)"をはじめとするBIに多数引用され、多くのユーザーに毎日クエリされるので、「クエリごとのコスト」と「BIツールの挙動」という二つの観点から見て、費用対効果が劇的に改善するため、必ず保持してください(251020)
WITH     
    info_before_entrance_analysis AS ( -- 各種帳票に引用するための項目を整理
        SELECT
            t2.id                                           -- account_job_seeker由来の18桁ID
            , t1.cd__c                                      -- account_job_seeker由来のSFID
            , t1.contact_month1 AS contact_month            -- 接触月
            , t1.contact_date                               -- 接触日
            , DATE_TRUNC(t1.contact_month1 , QUARTER) AS contact_quarter -- 接触四半期
            , CASE 
                WHEN t1.entry_route = 'CRM' AND t1.judge_entry_route LIKE '%再登録%' AND t1.judge_entry_route NOT LIKE '%LINE%' AND t1.judge_entry_route NOT LIKE '%友人紹介%' THEN 'CRM再登録'
                WHEN t1.entry_route = 'NU' THEN 'NU経路'
                ELSE '通常KPI' 
            END AS category                                 -- 流入経路における大分類 ※2021年頃の当時の区分に過ぎない(250202 KI追記)
            , t1.entry_route                                -- 流入経路における分類
            , t1.judge_entry_route                          -- 流入経路における判定
            , CASE
                WHEN t1.occupation IN ('介護職', '看護師', '保育士', '栄養士', 'デンタル') 
                    AND 
                        (
                            REGEXP_CONTAINS(t1.utmcampaign__c, '^CPF_[0-9]{6}$') = TRUE AND REGEXP_EXTRACT(t1.utmcampaign__c, 'CPF_(.*)') = LEFT(REPLACE(CAST(contact_month1 AS STRING), '-', ''), 6)
                            OR REGEXP_CONTAINS(t1.utmcampaign__c, '^PM_[0-9]{6}CPF$') = TRUE AND REGEXP_EXTRACT(t1.utmcampaign__c, 'PM_(.*)CPF') = LEFT(REPLACE(CAST(contact_month1 AS STRING), '-', ''), 6)
                            OR REGEXP_CONTAINS(t1.utmcampaign__c, '^richmenu_[0-9]{6}CPF$') = TRUE AND REGEXP_EXTRACT(t1.utmcampaign__c, 'richmenu_(.*)CPF') = LEFT(REPLACE(CAST(contact_month1 AS STRING), '-', ''), 6)
                            OR REGEXP_CONTAINS(t1.utmcampaign__c, '^shindan_[0-9]{6}(b|d)$') = TRUE AND REGEXP_EXTRACT(t1.utmcampaign__c, 'shindan_(.*).{1}') = LEFT(REPLACE(CAST(contact_month1 AS STRING), '-', ''), 6)
                        )
                        THEN 'CPF当月'                       -- utmcampaign__cが特定の条件を満たし、かつその値に含まれるyyyymmが「接触月」の場合
                WHEN t1.occupation IN ('介護職', '看護師', '保育士', '栄養士', 'デンタル') 
                    AND 
                        (
                            REGEXP_CONTAINS(t1.utmcampaign__c, '^CPF_[0-9]{6}$') = TRUE AND CAST(REGEXP_EXTRACT(t1.utmcampaign__c, 'CPF_(.*)') AS INTEGER) <= CAST(LEFT(REPLACE(CAST(DATE_ADD(contact_month1, INTERVAL -1 MONTH) AS STRING), '-', ''), 6) AS INTEGER)
                            OR REGEXP_CONTAINS(t1.utmcampaign__c, '^PM_[0-9]{6}CPF$') = TRUE AND CAST(REGEXP_EXTRACT(t1.utmcampaign__c, 'PM_(.*)CPF') AS INTEGER) <= CAST(LEFT(REPLACE(CAST(DATE_ADD(contact_month1, INTERVAL -1 MONTH) AS STRING), '-', ''), 6) AS INTEGER)
                            OR REGEXP_CONTAINS(t1.utmcampaign__c, '^richmenu_[0-9]{6}CPF$') = TRUE AND CAST(REGEXP_EXTRACT(t1.utmcampaign__c, 'richmenu_(.*)CPF') AS INTEGER) <= CAST(LEFT(REPLACE(CAST(DATE_ADD(contact_month1, INTERVAL -1 MONTH) AS STRING), '-', ''), 6) AS INTEGER)
                            OR REGEXP_CONTAINS(t1.utmcampaign__c, '^shindan_[0-9]{6}(b|d)$') = TRUE AND CAST(REGEXP_EXTRACT(t1.utmcampaign__c, 'shindan_(.*).{1}') AS INTEGER) <= CAST(LEFT(REPLACE(CAST(DATE_ADD(contact_month1, INTERVAL -1 MONTH) AS STRING), '-', ''), 6) AS INTEGER)
                        )
                        THEN 'CPFストック'                   -- utmcampaign__cが特定の条件を満たし、かつその値に含まれるyyyymmが「接触月」より前の場合
                WHEN t1.occupation IN ('介護職', '看護師', '保育士', '栄養士') AND t1.utmsource__c = 'instagram' AND t1.utmmedium__c = 'CRM' THEN 'instagram'
                WHEN t1.occupation IN ('介護職', '看護師', '保育士', 'POS', '技師','デンタル', '栄養士') AND t1.utmsource__c = 'twitter' THEN 'twitter'
                WHEN t1.occupation IN ('介護職', '看護師', '保育士', '栄養士') AND t1.utmcampaign__c IN ('OS', 'hearing') THEN 'OS施策'
                WHEN t1.occupation IN ('保育士') AND REGEXP_CONTAINS(t1.utmcampaign__c, 'lineat') = TRUE THEN '保育/栄養士のお仕事'
                WHEN t1.occupation IN ('栄養士') AND REGEXP_CONTAINS(t1.utmsource__c, 'crm_lineat') AND (REGEXP_CONTAINS(t1.utmmedium__c, 'CRM') OR REGEXP_CONTAINS(t1.utmmedium__c, 'social'))= TRUE THEN '保育/栄養士のお仕事'
                ELSE 'その他'
            END AS line_registration_route                  -- CRM/LINEにおける登録経路判定 (CRM課からの要望により、240410 KI追加)
            , t1.followupchangedmonth__pc                   -- 営業⇒NU連携月
            , t1.followupchangeddate__c                     -- 営業⇒NU連携日
            , t1.numutemonth__pc                            -- NUミュート月
            , t1.numuteday__pc                              -- NUミュート日
            , t1.occupation                                 -- 職種
            , t1.occupation_flg                             -- 特定の職種（カレッジ、派遣を含む職種）を除外するためのフラグ
            , t1.area_no                                    -- 支社並び替えに活用する支社No.
            , t1.area                                       -- 支社
            , t1.prefecture_name                            -- 都道府県
            , t2.billing_city                               -- 市
            , t1.medium                                     -- 媒体
            , CASE 
                WHEN t1.name = '削除希望' THEN t1.name
                ELSE REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(UPPER(NORMALIZE(t1.name,NFKC)),' ',''),'削除',''),'退職',''),'不要',''),'【不要】',''),')',''),'(','') 
            END AS name                                     -- 営業担当名
            , t1.owner_id                                   -- 営業担当ID
            , t5.digital_support_target__c                  -- 交渉中デジタルサポート対象CA
            , t4.area AS sales_area                         -- 営業支社
            , t4.sales_office AS sales_office               -- 営業所
            , CASE 
                WHEN t1.occupation = '施工管理' THEN t3.registration_date_time__c ELSE t2.registration_date_time__c 
                END AS registration_date_time__c            -- 新規登録時における登録時間
            , EXTRACT(DAYOFWEEK FROM DATE(t1.contact_date)) AS tourokuyoubi__c -- 接触曜日
            , t1.step0_5                                    -- 通電日
            , t1.step1                                      -- ヒアリング日
            , t1.step2                                      -- 求人提案日/社内面接日決定日
            , t1.step3                                      -- 面接日決定日/売込み日
            , t1.step4                                      -- 面接実施日/業確日
            , t1.step5                                      -- 内定連絡日/配属日決定日
            , t1.record_date                                -- 計上日
            , t1.retire_date                                -- 辞退退職日
            , t1.retire_category                            -- 辞退退職情報
            , t1.retire_leadtime                            -- 入職予定日に対する辞退退職までのリードタイム
            , t1.expected_date_of_employment__c             -- 入職予定日
            , t1.count_send_date_1                          -- ステップ1におけるKPI〆日
            , t1.count_send_date_2                          -- ステップ2におけるKPI〆日
            , t1.count_send_date_3                          -- ステップ3におけるKPI〆日
            , t1.count_send_date_4                          -- ステップ4におけるKPI〆日
            , t1.job_change_time_from__c                    -- 転職希望時期開始
            , t1.contact_workday                            -- 接触営業日
            , t1.step0_5_workday                            -- ステップ0.5営業日
            , t1.step1_workday                              -- ステップ1営業日
            , t1.step2_workday                              -- ステップ2営業日
            , t1.step3_workday                              -- ステップ3営業日
            , t1.step4_workday                              -- ステップ4営業日
            , t1.step5_workday                              -- ステップ5営業日
            , t1.last_workday                               -- 接触月末営業日
            , t1.workday_calculation_thismonth_1            -- 当月起算集計〆営業日
            , t1.workday_calculation_lastmonth_1            -- 前月起算集計〆営業日
            , t1.utmsource__c                               -- utm情報
            , t1.utmmedium__c                               -- utm情報
            , t1.utmcampaign__c                             -- utm情報
            , t1.utmcontent__c                              -- utm情報
            , t1.utmterm__c                                 -- utm情報
            , t1.reregisterutmsource__c                     -- CRM再登録utm情報
            , t1.reregisterutmmedium__c                     -- CRM再登録utm情報
            , t1.reregisterutmcampaign__c                   -- CRM再登録utm情報
            , t1.reregisterutmcontent__c                    -- CRM再登録utm情報
            , t1.reregisterutmterm__c                       -- CRM再登録utm情報
            , t1.registration_date__c                       -- 新規登録日
            , t1.registration_route_hoikunooshigoto__c      -- 登録経路（保育のお仕事）
            , t1.registration_route_eiyoshinooshigoto__c    -- 登録経路（栄養士のお仕事）
            
            -- 質に関する項目 --
            , t1.sex__c                                     -- 性別
            , t1.age__c                                     -- 年齢
            , CASE 
                WHEN t1.occupation = 'POS' AND t1.age__c IS NOT NULL AND t1.age__c <= 22 THEN '22歳以下'
                WHEN t1.occupation = 'POS' AND t1.age__c IS NOT NULL AND t1.age__c > 22 AND t1.age__c < 30 THEN '22歳以上20代'
                ELSE t1.age_group 
            END AS age_group                                -- 整形した年齢層
            , t1.age_group__c                               -- 整形する前の年齢層
            , CASE    
                WHEN t1.occupation = '看護師' THEN 
                    CASE 
                        WHEN t1.work_style IS NULL THEN 'その他'
                        WHEN t1.work_style = '常勤(夜勤あり)' OR t1.work_style = '常勤(夜勤可能)' OR t1.work_style = '常勤夜勤あり' OR t1.work_style LIKE '%フル%' THEN 'フル常勤'
                        WHEN t1.work_style = '常勤(日勤常勤)' OR t1.work_style = '常勤(日勤のみ)' OR t1.work_style = '日勤常勤' THEN '日勤常勤'
                        WHEN t1.work_style = '常勤(夜勤のみ)' OR t1.work_style = '常勤夜勤のみ' OR t1.work_style = '夜勤常勤' THEN '夜勤常勤'
                        WHEN t1.work_style = '非常勤' OR t1.work_style = '非常勤(パート)' OR t1.work_style = 'パート' OR t1.work_style = 'パート・アルバイト' OR t1.work_style = 'フルタイムパート' THEN '非常勤'
                        WHEN t1.work_style = '夜勤バイト' OR t1.work_style = '夜勤アルバイト' THEN '夜勤バイト'
                        WHEN t1.work_style LIKE '%応援%' THEN '応援看護師'
                        WHEN t1.work_style = '派遣' OR t1.work_style = '紹介予定派遣' THEN '派遣'
                        WHEN t1.work_style = '常勤' OR t1.work_style = '正社員' THEN 'その他常勤' 
                        ELSE 'その他' 
                    END
                WHEN t1.work_style IS NULL THEN 'その他' 
                ELSE t1.work_style 
            END AS work_style                               -- 雇用形態整形
            , CASE 
                WHEN t1.timing = '9か月以内' THEN '1年以内' 
                WHEN t1.timing = '-' THEN 'その他' 
                ELSE t1.timing 
            END AS timing                                   -- 希望時期整形
            , CASE 
                WHEN t1.occupation = '介護職' THEN 
                    CASE 
                        WHEN t1.yuusensikakusyuukeiyou__c IS NULL THEN 'その他'			
                        WHEN t1.yuusensikakusyuukeiyou__c LIKE '%ケアマネージャー%' THEN 'ケアマネージャー'			
                        WHEN t1.yuusensikakusyuukeiyou__c LIKE '%サービス管理責任者研修%' THEN 'サービス管理責任者研修'			
                        WHEN t1.yuusensikakusyuukeiyou__c LIKE '%ヘルパー１級%' THEN 'ヘルパー１級'			
                        WHEN t1.yuusensikakusyuukeiyou__c LIKE '%ヘルパー２級%' THEN 'ヘルパー２級'			
                        WHEN t1.yuusensikakusyuukeiyou__c LIKE '%ユニットリーダー研修%' THEN 'ユニットリーダー研修'			
                        WHEN t1.yuusensikakusyuukeiyou__c LIKE '%移動介護従事者%' THEN '移動介護従事者'			
                        WHEN t1.yuusensikakusyuukeiyou__c LIKE '%介護支援専門員%' THEN '介護支援専門員'			
                        WHEN t1.yuusensikakusyuukeiyou__c LIKE '%介護職員基礎研修%' THEN '介護職員基礎研修'			
                        WHEN t1.yuusensikakusyuukeiyou__c LIKE '%介護職員実務者研修%' THEN '介護職員実務者研修'			
                        WHEN t1.yuusensikakusyuukeiyou__c LIKE '%介護職員初任者研修%' THEN '介護職員初任者研修'			
                        WHEN t1.yuusensikakusyuukeiyou__c LIKE '%介護福祉士%' THEN '介護福祉士'	
                        WHEN t1.yuusensikakusyuukeiyou__c LIKE '%児童発達支援管理責任者研修%' THEN '児童発達支援管理責任者研修'
                        WHEN t1.yuusensikakusyuukeiyou__c LIKE '%社会福祉士%' THEN '社会福祉士'			
                        WHEN t1.yuusensikakusyuukeiyou__c LIKE '%社会福祉主事%' THEN '社会福祉主事'			
                        WHEN t1.yuusensikakusyuukeiyou__c LIKE '%主任介護支援専門員%' THEN '主任介護支援専門員'		
                        WHEN t1.yuusensikakusyuukeiyou__c LIKE '%精神保健福祉士%' THEN '精神保健福祉士'		
                        WHEN t1.yuusensikakusyuukeiyou__c LIKE '%相談支援専門員%' THEN '相談支援専門員'		
                        WHEN t1.yuusensikakusyuukeiyou__c LIKE '%認知症介護実践者研修%' THEN '認知症介護実践者研修'		
                        WHEN t1.yuusensikakusyuukeiyou__c LIKE '%認知症対応型サービス事業管理者研修%' THEN '認知症対応型サービス事業管理者研修'
                        WHEN t1.yuusensikakusyuukeiyou__c LIKE '%資格取得見込み%' THEN '資格取得見込み'
                        WHEN t1.yuusensikakusyuukeiyou__c LIKE '%資格なし%' THEN '資格なし'
                        ELSE 'その他' 
                    END	
                WHEN t1.occupation = '看護師' THEN 
                    CASE 
                        WHEN t1.yuusensikakusyuukeiyou__c IS NULL THEN 'その他'			
                        WHEN t1.yuusensikakusyuukeiyou__c LIKE '%正看護師%' THEN '正看護師'
                        WHEN t1.yuusensikakusyuukeiyou__c LIKE '%准看護師%' THEN '准看護師'			
                        WHEN t1.yuusensikakusyuukeiyou__c LIKE '%助産師%' THEN '助産師'			
                        WHEN t1.yuusensikakusyuukeiyou__c LIKE '%保健師%' THEN '保健師'			
                        WHEN t1.yuusensikakusyuukeiyou__c LIKE '%資格取得見込み%' THEN '資格取得見込み'
                        WHEN t1.yuusensikakusyuukeiyou__c LIKE '%資格なし%' THEN '資格なし'
                        ELSE 'その他' 
                    END
                WHEN t1.occupation = '保育士' THEN 
                    CASE 
                        WHEN t1.yuusensikakusyuukeiyou__c IS NULL THEN 'その他'			
                        WHEN t1.yuusensikakusyuukeiyou__c LIKE '%保育士%' THEN '保育士'			
                        WHEN t1.yuusensikakusyuukeiyou__c LIKE '%幼稚園教諭%' THEN '幼稚園教諭'		
                        WHEN t1.yuusensikakusyuukeiyou__c LIKE '%資格取得見込み%' THEN '資格取得見込み'
                        WHEN t1.yuusensikakusyuukeiyou__c LIKE '%資格なし%' THEN '資格なし'	
                        ELSE 'その他' 
                    END
                WHEN t1.occupation = 'POS' THEN 
                    CASE 
                        WHEN t1.yuusensikakusyuukeiyou__c IS NULL THEN 'その他'			
                        WHEN t1.yuusensikakusyuukeiyou__c LIKE '%言語聴覚士%' THEN '言語聴覚士'			
                        WHEN t1.yuusensikakusyuukeiyou__c LIKE '%作業療法士%' THEN '作業療法士'			
                        WHEN t1.yuusensikakusyuukeiyou__c LIKE '%理学療法士%' THEN '理学療法士'		
                        WHEN t1.yuusensikakusyuukeiyou__c LIKE '%柔道整復師%' THEN '柔道整復師'	
                        WHEN t1.yuusensikakusyuukeiyou__c LIKE '%薬剤師%' THEN '薬剤師'	
                        WHEN t1.yuusensikakusyuukeiyou__c LIKE '%あん摩マッサージ指圧師%' THEN 'あん摩マッサージ指圧師'	
                        WHEN t1.yuusensikakusyuukeiyou__c LIKE '%鍼灸師%' THEN '鍼灸師'	
                        WHEN t1.yuusensikakusyuukeiyou__c LIKE '%資格取得見込み%' THEN '資格取得見込み'
                        WHEN t1.yuusensikakusyuukeiyou__c LIKE '%資格なし%' THEN '資格なし'	
                        ELSE 'その他' 
                    END
                WHEN t1.occupation = '技師' THEN 
                    CASE 
                        WHEN t1.yuusensikakusyuukeiyou__c IS NULL THEN 'その他'			
                        WHEN t1.yuusensikakusyuukeiyou__c LIKE '%臨床検査技師%' THEN '臨床検査技師'			
                        WHEN t1.yuusensikakusyuukeiyou__c LIKE '%臨床工学技士%' THEN '臨床工学技士'			
                        WHEN t1.yuusensikakusyuukeiyou__c LIKE '%診療放射線技師%' THEN '診療放射線技師'	
                        WHEN t1.yuusensikakusyuukeiyou__c LIKE '%資格取得見込み%' THEN '資格取得見込み'
                        WHEN t1.yuusensikakusyuukeiyou__c LIKE '%資格なし%' THEN '資格なし'	
                        ELSE 'その他' 
                    END			
                WHEN t1.occupation = 'デンタル' THEN 
                    CASE 
                        WHEN t1.yuusensikakusyuukeiyou__c IS NULL THEN 'その他'			
                        WHEN t1.yuusensikakusyuukeiyou__c LIKE '%歯科医師%' THEN '歯科医師'
                        WHEN t1.yuusensikakusyuukeiyou__c LIKE '%歯科衛生士%' THEN '歯科衛生士'
                        WHEN t1.yuusensikakusyuukeiyou__c LIKE '%資格取得見込み%' THEN '資格取得見込み'
                        WHEN t1.yuusensikakusyuukeiyou__c LIKE '%資格なし%' THEN '資格なし' 
                        ELSE 'その他' 
                    END		
                WHEN t1.occupation = '栄養士' THEN 
                    CASE 
                        WHEN t1.yuusensikakusyuukeiyou__c IS NULL THEN 'その他'
                        WHEN t1.yuusensikakusyuukeiyou__c LIKE '%管理栄養士%' THEN '管理栄養士'	
                        WHEN t1.yuusensikakusyuukeiyou__c LIKE '%栄養士%' THEN '栄養士'			
                        WHEN t1.yuusensikakusyuukeiyou__c LIKE '%調理師%' THEN '調理師'		
                        WHEN t1.yuusensikakusyuukeiyou__c LIKE '%資格取得見込み%' THEN '資格取得見込み'
                        WHEN t1.yuusensikakusyuukeiyou__c LIKE '%資格なし%' THEN '資格なし'	
                        ELSE 'その他' 
                    END
                WHEN t1.yuusensikakusyuukeiyou__c IS NULL THEN 'その他'			
                WHEN t1.yuusensikakusyuukeiyou__c LIKE '%取得見込%' THEN '資格取得見込み'			
                ELSE t1.yuusensikakusyuukeiyou__c 
            END AS yuusensikakusyuukeiyou__c                        -- 整形した資格
            , t1.qualification                                      -- 資格有無
            , t1.rt_flg                                             -- 技師におけるRTフラグ
            , t1.mt_flg                                             -- 技師におけるMTフラグ
            , t1.status__c                                          -- 求職者ステータス
            , t1.referral_status__c                                 -- 求職者の紹介ステータス
            , t1.const_desired_1                                    -- 施工管理における希望職種：建築施工管理
            , t1.const_desired_2                                    -- 施工管理における希望職種：土木施工管理
            , t1.const_desired_3                                    -- 施工管理における希望職種：電気施工管理
            , t1.const_desired_4                                    -- 施工管理における希望職種：電気設備管理
            , t1.const_desired_5                                    -- 施工管理における希望職種：施工図・設計
            , t1.const_desired_6                                    -- 施工管理における希望職種：施工図作成
            , t1.const_desired_7                                    -- 施工管理における希望職種：空調設備施工管理
            , t1.const_desired_8                                    -- 施工管理における希望職種：CADオペレーター
            , t1.const_desired_9                                    -- 施工管理における希望職種：設備施工管理
            , t1.const_desired_10                                   -- 施工管理における希望職種：衛生設備施工管理
            , t1.const_desired_11                                   -- 施工管理における希望職種：プラント施工管理
            , t1.const_desired_12                                   -- 施工管理における希望職種：計装
            , t1.const_desired_13                                   -- 施工管理における希望職種：その他
            , t1.construction_management_experience                 -- 施工管理経験者
            , t1.construction_industry_experience                   -- 施工管理業界経験者
            , t1.vaccine_flg                                        -- ワクチン集客フラグ
            , t1.entrance_flag                                      -- 入口フラグ(接触数カウントから除外するために活用)
            , CASE 
                WHEN t1.judge_entry_route LIKE '%新規%' THEN t2.web_job_application_number__c 
                ELSE NULL 
            END AS web_job_application_number__c                    -- Web登録時応募求人番号
            , CASE 
                WHEN t1.utmcampaign__c <> "hearing" OR t1.utmcampaign__c IS NULL THEN 1
                ELSE 0
            END AS hearing_except_flag                              --utmcampaign__cがhearingを除外するために活用
            
            -- 数に関する項目 --
            , t1.actual_count1                                      -- KPI実績 (紹介事業は面接設定数、施工は登録数)
            , t1.expected_contact_count1                            -- 着地接触数
            , t1.expected_actual_count1                             -- KPI実績着地見込み (紹介事業は面接設定数、施工は登録数)
            , t1.actual_count_same_workday_comparison1              -- 当月起算同営業日におけるKPI実績 (紹介事業は面接設定数、施工は登録数)
            , t1.actual_count_same_workday_comparison2              -- 前月起算同営業日におけるKPI実績 (紹介事業は面接設定数、施工は登録数)
            , t1.contact_count1                                     -- 接触数
            , t1.cvv                                                -- CVV情報
            , t1.n_cvv                                              -- 次回のCVV情報
            , t1.experience_count1                                  -- 施工管理における経験者数
            , t1.young_experience_count1                            -- 施工管理における若年層経験者数
            , t1.step0_5_count_for_rate1                            -- 通電数
            , t1.step1_count_for_rate1                              -- ヒアリング数
            , t1.step2_count_for_rate1                              -- 求人提案数/社内面接日決定数
            , t1.step3_count_for_rate1                              -- 面接日決定数/売込み数
            , t1.step4_count_for_rate1                              -- 面接実施数/業確数
            , t1.step5_count_for_rate1                              -- 内定連絡数/配属日決定数
            , t1.record_count_for_rate1                             -- 計上数
            , t1.sales_amount__c AS gross_amount                    -- グロス売上
            , t1.amount AS amount                                   -- 純契約売上
            , t1.f_6_amount__c                                      -- 施工管理における初回受注後6カ月以内受注での売上
            , t1.f_12_amount__c                                     -- 施工管理における初回受注後12カ月以内受注での売上
            , t1.f_24_amount__c                                     -- 施工管理における初回受注後24カ月以内受注での売上
            , t1.contact_count_same_workday_comparison1             -- 当月起算同営業日における接触数
            , t1.contact_count_same_workday_comparison2             -- 前月起算同営業日における接触数
            , t1.experience_count_same_workday_comparison1          -- 当月起算同営業日における経験者数
            , t1.experience_count_same_workday_comparison2          -- 前月起算同営業日における経験者数
            , t1.young_experience_count_same_workday_comparison1    -- 当月起算同営業日における若年層経験者数
            , t1.young_experience_count_same_workday_comparison2    -- 前月起算同営業日における若年層経験者数
            , t1.step0_5_count_same_workday_comparison1             -- 当月起算同営業日におけるステップ0.5数
            , t1.step0_5_count_same_workday_comparison2             -- 前月起算同営業日におけるステップ0.5数
            , t1.step1_count_same_workday_comparison1               -- 当月起算同営業日におけるステップ1数
            , t1.step1_count_same_workday_comparison2               -- 前月起算同営業日におけるステップ1数
            , t1.step2_count_same_workday_comparison1               -- 当月起算同営業日におけるステップ2数
            , t1.step2_count_same_workday_comparison2               -- 前月起算同営業日におけるステップ2数
            , t1.step3_count_same_workday_comparison1               -- 当月起算同営業日におけるステップ3数
            , t1.step3_count_same_workday_comparison2               -- 前月起算同営業日におけるステップ3数
            , t1.step4_count_same_workday_comparison1               -- 当月起算同営業日におけるステップ4数
            , t1.step4_count_same_workday_comparison2               -- 前月起算同営業日におけるステップ4数
            , t1.step5_count_same_workday_comparison1               -- 当月起算同営業日におけるステップ5数
            , t1.step5_count_same_workday_comparison2               -- 前月起算同営業日におけるステップ5数
            , t1.step3_pred                                         -- DX推進室による予測モデルを引用：想定ステップ3転換確率(代理店向けCSVファイルでの名称：ステップ3転換確率_AI予測モデル)
            , t1.expected_sales                                     -- DX推進室による予測モデルを引用：想定売上価値(代理店向けCSVファイルでの名称：想定売上_AI予測モデル)
            , t1.step3_pred_v2                                      -- DX推進室による予測モデルを引用：想定ステップ3転換確率v2
            , t1.expected_sales_v2                                  -- DX推進室による予測モデルを引用：想定売上価値v2
            , t1.step3_pred_divided_by_mean                         -- DX推進室による予測モデルを引用：獲得時点求職者価値（対セグメント平均）(代理店向けCSVファイルでの名称：CVV_AI予測モデル)
            , t1.modified_gross_expected_sales                      -- DX推進室による予測モデルを引用：想定売上価値(代理店向けCSVファイルでの名称：想定グロス売上(修正版)_AI予測モデル)
            , t1.expected_sales_v3 -- -- DX推進室による予測モデルを引用：想定売上価値v3,20260916山崎追記
        FROM `tryt-bigquery-pj.marketing_edit_v2.01_06_02_before_daily_share` AS t1
        LEFT JOIN `tryt-bigquery-pj.marketing_edit_v2.01_00_career_account_job_seeker_temp_field` AS t2
            ON t1.cd__c = t2.cd__c
        LEFT JOIN `tryt-bigquery-pj.marketing_edit_v2.01_00_const_account_job_seeker_temp_field` AS t3
            ON t1.cd__c = t3.cd__c
        LEFT JOIN `tryt-bigquery-pj.production_tryt.master_sales_office` AS t4 -- 営業所マスタ https://docs.google.com/spreadsheets/d/1se4E_tSOTM50Td9WsTmpYhpLd3_CIYQMjYT36uupTVc/edit?gid=1620852360#gid=1620852360
            ON t1.department_in_charge__c = t4.branch_flag
        LEFT JOIN `tryt-bigquery-pj.production_tryt_informatica.career_user` AS t5 
            ON t1.owner_id = t5.id
        )

    , re_define_route_registration AS ( -- entry_routeを再分類したrouteカラムを作成、登録区分の判定カラムを作成
        SELECT
            *
            ,CASE
                WHEN category = '通常KPI' THEN entry_route
                WHEN category = 'CRM再登録' THEN 'CRM'
                WHEN category = 'NU経路' THEN 'NU'
                ELSE NULL
            END AS route
            ,CASE
                WHEN REGEXP_CONTAINS(judge_entry_route, '新規') THEN '新規'
                WHEN REGEXP_CONTAINS(judge_entry_route, '再登録') THEN '再登録'
            END AS reg_judge
        FROM info_before_entrance_analysis
        )
    
    , define_work_style_field AS ( -- work_style_mstから常勤/非常勤判定用のフラグ作成, コア層の判定フラグ作成 【重要】25年5月現在におけるコア層の定義は右記ファイルに纏められているが今後変更の可能性があるため現場担当者と擦り合わせること https://trytgroup.sharepoint.com/:x:/r/sites/marketing/_layouts/15/Doc.aspx?sourcedoc=%7B5FB0D1D8-00CB-49A3-BB5D-F18D7EB0A974%7D&file=%E3%82%B3%E3%82%A2%E5%B1%A4%20%E5%AE%9A%E7%BE%A9%E6%A4%9C%E8%A8%8E%E7%94%A8_240710.xlsx&action=default&mobileredirect=true
 SELECT 
            b1.*
            ,CASE
                WHEN b1.occupation = '介護職' THEN
                    CASE
                        WHEN 
                            timing IN ('1か月以内', '3か月以内')
                            AND yuusensikakusyuukeiyou__c IN ('介護支援専門員','ヘルパー２級','介護職員実務者研修','介護職員初任者研修','介護福祉士') AND yuusensikakusyuukeiyou__c IS NOT NULL --主要5資格の追加,20260916山崎追記
                            AND (s1.work_style IN('常勤','常勤(正社員)','常勤(日勤のみ)','常勤(日勤常勤)','常勤(夜勤可能)','常勤夜勤あり','常勤夜勤のみ','正社員','日勤常勤','夜勤常勤','常勤(夜勤あり)')) -- 常勤に該当する項目の追加,20260916山崎追記
                            THEN 1 -- 介護 コア層用フラグ
                        ELSE 0
                    END
                WHEN occupation = '看護師' THEN
                    CASE
                        WHEN 
                            timing IN ('1か月以内', '3か月以内', '6か月以内') 
                            AND yuusensikakusyuukeiyou__c NOT IN ('資格なし', 'その他', '資格取得見込み', '資格なし（職種経験無）', '資格なし（職種経験有）') AND yuusensikakusyuukeiyou__c IS NOT NULL
                            AND (
                              (s1.work_style IS NOT NULL AND s1.full_time = 1) 
                              OR
                              (s1.work_style IN('夜勤バイト','応援看護師'))     --【UT.ISHIKAWA 251027追加】
                              )
                            THEN 1 -- 看護 コア層用フラグ
                        ELSE 0
                    END
                 WHEN occupation = '保育士' THEN
                    CASE 
                        WHEN timing IN ('1か月以内', '3か月以内')
                            AND FORMAT_DATE('%m-%d', contact_month) BETWEEN '04-01' AND '09-01' 
                            AND yuusensikakusyuukeiyou__c IN ('保育士', '幼稚園教諭', 'その他') AND yuusensikakusyuukeiyou__c IS NOT NULL
                            AND (s1.work_style IS NOT NULL AND s1.full_time = 1)
                            THEN 1
                    --202507以前のコア条件
                        WHEN
                            timing IN ('1か月以内', '3か月以内','6か月以内') 
                            AND contact_month < DATE '2025-08-01'
                            AND FORMAT_DATE('%m-%d', contact_month) BETWEEN '10-01' AND '12-01' 
                            AND yuusensikakusyuukeiyou__c IN ('保育士', '幼稚園教諭', 'その他') AND yuusensikakusyuukeiyou__c IS NOT NULL
                            AND (s1.work_style IS NOT NULL AND s1.full_time = 1)
                            THEN 1
                        WHEN timing IN ('1か月以内', '3か月以内')
                            AND contact_month < DATE '2025-08-01'
                            AND FORMAT_DATE('%m-%d', contact_month) BETWEEN '01-01' AND '03-01'
                            AND yuusensikakusyuukeiyou__c IN ('保育士', '幼稚園教諭', 'その他') AND yuusensikakusyuukeiyou__c IS NOT NULL
                            AND (s1.work_style IS NOT NULL AND (s1.full_time = 1 OR s1.full_time = 0))
                            THEN 1
                    --202508以降のコア条件    
                        WHEN
                            timing IN ('1か月以内', '3か月以内','6か月以内','2026年4月')  ----- 20250714変更: 注意;"2027年4月"がコア層の定義になる際は手動変更する必要あり
                            AND contact_month >= DATE '2025-08-01'
                            AND FORMAT_DATE('%m-%d', contact_month) BETWEEN '10-01' AND '12-01' 
                            AND yuusensikakusyuukeiyou__c IN ('保育士', '幼稚園教諭', 'その他') AND yuusensikakusyuukeiyou__c IS NOT NULL
                            AND (s1.work_style IS NOT NULL AND s1.full_time = 1)
                            THEN 1
                        WHEN timing IN ('1か月以内', '3か月以内', '2026年4月')
                            AND contact_month >= DATE '2025-08-01'
                            AND FORMAT_DATE('%m-%d', contact_month) BETWEEN '01-01' AND '03-01'
                            AND yuusensikakusyuukeiyou__c IN ('保育士', '幼稚園教諭', 'その他') AND yuusensikakusyuukeiyou__c IS NOT NULL
                            AND (s1.work_style IS NOT NULL AND (s1.full_time = 1 OR s1.full_time = 0))
                            THEN 1
                          --保育 コア層用フラグ,20260916山崎追記
                        ELSE 0
                    END
                WHEN occupation = 'POS' THEN
                    CASE
                        WHEN 
                            timing IN ('1か月以内', '3か月以内', '6か月以内') 
                            AND yuusensikakusyuukeiyou__c IN ('理学療法士', '作業療法士', '言語聴覚士') AND yuusensikakusyuukeiyou__c IS NOT NULL -- 柔道整復師を削除、20260916山崎追記
                            AND (s1.work_style IS NOT NULL AND s1.full_time = 1)
                            THEN 1 --PTOTST コア層用フラグ
                        ELSE 0
                    END
                WHEN occupation = '技師' THEN
                    CASE
                        WHEN
                            timing IN ('1か月以内', '3か月以内', '6か月以内')                        
                            THEN 1 --技師 コア層用フラグ
                        ELSE 0
                    END
                WHEN occupation = 'デンタル' THEN
                    CASE
                        WHEN 
                            timing IN ('1か月以内', '3か月以内')
                            AND yuusensikakusyuukeiyou__c NOT IN ('資格なし', 'その他', '資格取得見込み', '資格なし（職種経験無）', '資格なし（職種経験有）') AND yuusensikakusyuukeiyou__c IS NOT NULL
                            AND (s1.work_style IS NOT NULL AND s1.full_time = 1)
                            THEN 1 --デンタル コア層用フラグ
                        ELSE 0
                    END
                  WHEN occupation = '栄養士' THEN
                    CASE
                        WHEN 
                            timing IN ('1か月以内', '3か月以内')
                            AND yuusensikakusyuukeiyou__c NOT IN ('資格なし', 'その他', '資格取得見込み', '資格なし（職種経験無）', '資格なし（職種経験有）') AND yuusensikakusyuukeiyou__c IS NOT NULL
                            AND (s1.work_style IS NOT NULL AND s1.full_time = 1)
                            THEN 1 --栄養士 コア層用フラグ
                        ELSE 0
                    END
                  WHEN occupation = '調理師' THEN
                    CASE
                        WHEN 
                            timing IN ('1か月以内', '3か月以内')
                            AND yuusensikakusyuukeiyou__c IN ('調理師') AND yuusensikakusyuukeiyou__c IS NOT NULL
                            AND (s1.work_style IN ('常勤(夜勤可能)','常勤(日勤常勤)','常勤(夜勤あり)','常勤(日勤のみ)','常勤','常勤夜勤あり','常勤(正社員)','正社員','日勤常勤','常勤夜勤のみ','夜勤常勤')) 
                            THEN 1 --調理師 コア層用フラグの追加,20260916山崎追記
                        ELSE 0
                    END
                ELSE 0
            END AS work_style_classified ------ 20250717変更: 看護、技師を除く
            ,s1.full_time AS full_time_flg
        FROM re_define_route_registration AS b1
        LEFT JOIN `tryt-bigquery-pj.production_tryt.master_work_style` AS s1 -- 希望勤務形態マスタ https://docs.google.com/spreadsheets/d/1tVy_iOad8mgyKCzG3XVbcKyyphGx0dosTHpRBb9DR80/edit?gid=1262482520#gid=1262482520
            ON b1.work_style = s1.work_style
        )
    

--最終集計
SELECT 
          id,
          cd__c,
          contact_month,
          contact_date,
          contact_quarter,
          category,
          entry_route,
          judge_entry_route,
          line_registration_route,
          followupchangedmonth__pc,
          followupchangeddate__c,
          numutemonth__pc,
          numuteday__pc,
          occupation,
          occupation_flg,
          area_no,
          area,
          prefecture_name,
          billing_city,
          medium,
          name,
          owner_id,
          digital_support_target__c,
          sales_area,
          sales_office,
          registration_date_time__c,
          tourokuyoubi__c,
          step0_5,
          step1,
          step2,
          step3,
          step4,
          step5,
          record_date,
          retire_date,
          retire_category,
          retire_leadtime,
          expected_date_of_employment__c,
          count_send_date_1,
          count_send_date_2,
          count_send_date_3,
          count_send_date_4,
          job_change_time_from__c,
          contact_workday,
          step0_5_workday,
          step1_workday,
          step2_workday,
          step3_workday,
          step4_workday,
          step5_workday,
          last_workday,
          workday_calculation_thismonth_1,
          workday_calculation_lastmonth_1,
          utmsource__c,
          utmmedium__c,
          utmcampaign__c,
          utmcontent__c,
          utmterm__c,
          reregisterutmsource__c,
          reregisterutmmedium__c,
          reregisterutmcampaign__c,
          reregisterutmcontent__c,
          reregisterutmterm__c,
          registration_date__c,
          registration_route_hoikunooshigoto__c,
          registration_route_eiyoshinooshigoto__c,
          sex__c,
          age__c,
          age_group,
          age_group__c,
          work_style,
          timing,
          yuusensikakusyuukeiyou__c,
          qualification,
          rt_flg,
          mt_flg,
          status__c,
          referral_status__c,
          const_desired_1,
          const_desired_2,
          const_desired_3,
          const_desired_4,
          const_desired_5,
          const_desired_6,
          const_desired_7,
          const_desired_8,
          const_desired_9,
          const_desired_10,
          const_desired_11,
          const_desired_12,
          const_desired_13,
          construction_management_experience,
          construction_industry_experience,
          vaccine_flg,
          entrance_flag,
          web_job_application_number__c,
          hearing_except_flag,
          actual_count1,
          expected_contact_count1,
          expected_actual_count1,
          actual_count_same_workday_comparison1,
          actual_count_same_workday_comparison2,
          contact_count1,
          cvv,
          n_cvv,
          experience_count1,
          young_experience_count1,
          step0_5_count_for_rate1,
          step1_count_for_rate1,
          step2_count_for_rate1,
          step3_count_for_rate1,
          step4_count_for_rate1,
          step5_count_for_rate1,
          record_count_for_rate1,
          gross_amount,
          amount,
          f_6_amount__c,
          f_12_amount__c,
          f_24_amount__c,
          contact_count_same_workday_comparison1,
          contact_count_same_workday_comparison2,
          experience_count_same_workday_comparison1,
          experience_count_same_workday_comparison2,
          young_experience_count_same_workday_comparison1,
          young_experience_count_same_workday_comparison2,
          step0_5_count_same_workday_comparison1,
          step0_5_count_same_workday_comparison2,
          step1_count_same_workday_comparison1,
          step1_count_same_workday_comparison2,
          step2_count_same_workday_comparison1,
          step2_count_same_workday_comparison2,
          step3_count_same_workday_comparison1,
          step3_count_same_workday_comparison2,
          step4_count_same_workday_comparison1,
          step4_count_same_workday_comparison2,
          step5_count_same_workday_comparison1,
          step5_count_same_workday_comparison2,
          step3_pred,
          expected_sales,
          step3_pred_v2,
          expected_sales_v2,
          step3_pred_divided_by_mean,
          modified_gross_expected_sales,
          route,
          reg_judge,
          work_style_classified,
          full_time_flg,
          expected_sales_v3 -- expected_sales_v3を右端に配置するため、全カラム記入,20260916山崎追記 
FROM define_work_style_field;
-- marketing_edit_v2.01_07_before_entrance_analysis



-- marketing_edit_v2.01_09_01_before_exit_action_calc
    -- 更新日：2025/10/20
    -- 作業者：K.ISOZUMI
    -- 更新内容：パーティショニングとクラスタリングの設定

/*
■実行内容
出口発生月毎のコンタクト履歴由来の各種数値を集計するための処理を行う
(PK：id_pseudo_exit)
*/

CREATE OR REPLACE TABLE `tryt-bigquery-pj.marketing_edit_v2.01_09_01_before_exit_action_calc` PARTITION BY created_date CLUSTER BY action AS 
WITH 
    action_step0_5 AS ( -- step0.5アクション月における集計
        SELECT
            CONCAT(id_task, '_', 'step0_5') AS id_pseudo_exit
            , cd__c
            , birthday
            , created_date
            , DATE_TRUNC(created_date , MONTH) AS action_month
            , sales_name
            , owner_id
            , occupation
            , sales_office
            , branch
            , department_in_charge__c
            , 'step0_5' AS action
            , created_date AS step0_5
            , DATE(NULL) AS step1
            , DATE(NULL) AS step2
            , DATE(NULL) AS step3
            , DATE(NULL) AS step4
            , DATE(NULL) AS step5
            , DATE(NULL) AS record_date
            , CAST(NULL AS INT64) AS sales_amount__c                                        -- グロス売上
            , ROW_NUMBER() OVER(PARTITION BY cd__c , DATE_TRUNC(created_date , MONTH) ORDER BY created_date ASC) AS action_rank
        FROM `tryt-bigquery-pj.marketing_edit_v2.02_01_career_const_action_aggregated`
        WHERE action_category0_5  = 'step0.5'
            AND occupation IS NOT NULL
    ),

    action_step1 AS ( -- step1アクション月における集計
        SELECT
            CONCAT(id_task, '_', 'step1') AS id_pseudo_exit
            , cd__c
            , birthday
            , created_date
            , DATE_TRUNC(created_date , MONTH) AS action_month
            , sales_name
            , owner_id
            , occupation
            , sales_office
            , branch
            , department_in_charge__c
            , 'step1' AS action
            , DATE(NULL) AS step0_5
            , created_date AS step1
            , DATE(NULL) AS step2
            , DATE(NULL) AS step3
            , DATE(NULL) AS step4
            , DATE(NULL) AS step5
            , DATE(NULL) AS record_date
            , CAST(NULL AS INT64) AS sales_amount__c                                        -- グロス売上
            , ROW_NUMBER() OVER(PARTITION BY cd__c , DATE_TRUNC(created_date , MONTH) ORDER BY created_date ASC) AS action_rank
        FROM `tryt-bigquery-pj.marketing_edit_v2.02_01_career_const_action_aggregated`
        WHERE action_category = 'step1'
            AND occupation IS NOT NULL
    ),

    action_step2 AS ( -- step2アクション月における集計
        SELECT
            CONCAT(id_task, '_', 'step2') AS id_pseudo_exit
            , cd__c
            , birthday
            , created_date
            , DATE_TRUNC(created_date , MONTH) AS action_month
            , sales_name
            , owner_id
            , occupation
            , sales_office
            , branch
            , department_in_charge__c
            , 'step2' AS action
            , DATE(NULL) AS step0_5
            , DATE(NULL) AS step1
            , created_date AS step2
            , DATE(NULL) AS step3
            , DATE(NULL) AS step4
            , DATE(NULL) AS step5
            , DATE(NULL) AS record_date
            , CAST(NULL AS INT64) AS sales_amount__c                                        -- グロス売上
            , ROW_NUMBER() OVER(PARTITION BY cd__c , DATE_TRUNC(created_date , MONTH) ORDER BY created_date ASC) AS action_rank
        FROM `tryt-bigquery-pj.marketing_edit_v2.02_01_career_const_action_aggregated`
        WHERE action_category = 'step2'
            AND occupation IS NOT NULL
    ),

    action_step3 AS ( -- step3アクション月における集計
        SELECT
            CONCAT(id_task, '_', 'step3') AS id_pseudo_exit
            , cd__c
            , birthday
            , created_date
            , DATE_TRUNC(created_date , MONTH) AS action_month
            , sales_name
            , owner_id
            , occupation
            , sales_office
            , branch
            , department_in_charge__c
            , 'step3' AS action
            , DATE(NULL) AS step0_5
            , DATE(NULL) AS step1
            , DATE(NULL) AS step2
            , created_date AS step3
            , DATE(NULL) AS step4
            , DATE(NULL) AS step5
            , DATE(NULL) AS record_date
            , CAST(NULL AS INT64) AS sales_amount__c                                        -- グロス売上
            , ROW_NUMBER() OVER(PARTITION BY cd__c , DATE_TRUNC(created_date , MONTH) ORDER BY created_date ASC) AS action_rank
        FROM `tryt-bigquery-pj.marketing_edit_v2.02_01_career_const_action_aggregated`
        WHERE action_category = 'step3'
            AND occupation IS NOT NULL
    ),

    action_step4 AS ( -- step4アクション月における集計
        SELECT
            CONCAT(id_task, '_', 'step4') AS id_pseudo_exit
            , cd__c
            , birthday
            , created_date
            , DATE_TRUNC(created_date , MONTH) AS action_month
            , sales_name
            , owner_id
            , occupation
            , sales_office
            , branch
            , department_in_charge__c
            , 'step4' AS action
            , DATE(NULL) AS step0_5
            , DATE(NULL) AS step1
            , DATE(NULL) AS step2
            , DATE(NULL) AS step3
            , created_date AS step4
            , DATE(NULL) AS step5
            , DATE(NULL) AS record_date
            , CAST(NULL AS INT64) AS sales_amount__c                                        -- グロス売上
            , ROW_NUMBER() OVER(PARTITION BY cd__c , DATE_TRUNC(created_date , MONTH) ORDER BY created_date ASC) AS action_rank
        FROM `tryt-bigquery-pj.marketing_edit_v2.02_01_career_const_action_aggregated`
        WHERE action_category = 'step4'
            AND occupation IS NOT NULL
    ),

    action_step5 AS ( -- step5アクション月における集計
        SELECT
            CONCAT(id_task, '_', 'step5') AS id_pseudo_exit
            , cd__c
            , birthday
            , created_date
            , DATE_TRUNC(created_date , MONTH) AS action_month
            , sales_name
            , owner_id
            , occupation
            , sales_office
            , branch
            , department_in_charge__c
            , 'step5' AS action
            , DATE(NULL) AS step0_5
            , DATE(NULL) AS step1
            , DATE(NULL) AS step2
            , DATE(NULL) AS step3
            , DATE(NULL) AS step4
            , created_date AS step5
            , DATE(NULL) AS record_date
            , CAST(NULL AS INT64) AS sales_amount__c                                        -- グロス売上
            , ROW_NUMBER() OVER(PARTITION BY cd__c , DATE_TRUNC(created_date , MONTH) ORDER BY created_date ASC) AS action_rank
        FROM `tryt-bigquery-pj.marketing_edit_v2.02_01_career_const_action_aggregated`
        WHERE action_category = 'step5'
            AND occupation IS NOT NULL
    ),

    step_integrated AS ( -- 各stepにおける集計をユニオン
        SELECT * FROM action_step0_5
        UNION ALL
        SELECT * FROM action_step1 
        UNION ALL
        SELECT * FROM action_step2 
        UNION ALL
        SELECT * FROM action_step3 
        UNION ALL
        SELECT * FROM action_step4 
        UNION ALL
        SELECT * FROM action_step5
    )

--最終集計
SELECT 
    *
FROM step_integrated;
-- marketing_edit_v2.01_09_01_before_exit_action_calc



-- marketing_edit_v2.01_09_02_before_exit_route_judged
    -- 更新日：2026/07/17
    -- 作業者：細江
    -- 更新内容：タイムアウト（DEADLINE_EXCEEDED）エラーに伴うリファクタリング

/*
■実行内容
★★★どの経路が出口発生月毎における各アクションに寄与したかを「ラスト」で判定する 判定優先順位は下記の通り★★★
(PK：id_pseudo_exit)

1.登録日から3か月以内に成約のレコードがある場合         　      ⇒広告・SEO・通常CRM経由として判定する
2.CRM再登録から7日以内にヒアリング転換のレコードがある場合       ⇒CRM再登録経由として判定する
3.NU⇒営業連携から7日以内にヒアリング転換のレコードがある場合     ⇒NU経由として判定する
4.成約から遡り3カ月以内にCRM再登録のレコードがある場合          ⇒CRM再登録経由として判定する
5.成約から遡り3カ月以内にNU⇒営業連携のレコードがある場合        ⇒NU経由として判定する
6.上記のいずれにも該当しない場合に、経路を不明とする
*/

CREATE OR REPLACE TABLE `tryt-bigquery-pj.marketing_edit_v2.01_09_02_before_exit_route_judged` AS 
WITH
    entrance_history AS ( -- 入口情報を cd__c ごとに事前集約（ARRAY化）
        SELECT 
            cd__c
            , ARRAY_AGG(STRUCT(contact_date, contact_month, entry_route, judge_entry_route, step1) ORDER BY contact_month DESC, contact_date DESC) AS arr_history
        FROM `tryt-bigquery-pj.marketing_edit_v2.01_07_before_entrance_analysis`
        WHERE cd__c IS NOT NULL
        GROUP BY cd__c
    ),

    normal_classified AS ( -- コンタクト履歴に求職者情報を突合し、sfid/アクション/アクション日 の粒度でユニークに整理を行う/広告・SEO・通常CRM用
        SELECT
            t2.*
            , t1.cd__c
            , t1.action
            , t1.created_date
            , CASE 
                WHEN DATE_ADD(t2.contact_date , INTERVAL 3 MONTH) > t1.created_date THEN 1 
                ELSE 0 
            END AS marketing_route
        FROM `tryt-bigquery-pj.marketing_edit_v2.01_09_01_before_exit_action_calc` AS t1 --出口発生月ベースにおける各種数値を集計するための処理を行ったテーブル
        LEFT JOIN entrance_history AS t_hist
            ON t1.cd__c = t_hist.cd__c
        CROSS JOIN UNNEST(ARRAY(
            SELECT AS STRUCT h.contact_date, h.contact_month, h.entry_route, h.judge_entry_route
            FROM UNNEST(t_hist.arr_history) AS h
            WHERE h.contact_date <= t1.created_date
                AND h.entry_route <> 'NU'
                AND NOT (h.entry_route = 'CRM' AND h.judge_entry_route LIKE '%再登録%' AND h.judge_entry_route NOT LIKE '%LINE%' AND h.judge_entry_route NOT LIKE '%友人紹介%')
            ORDER BY h.contact_date DESC
            LIMIT 1
        )) AS t2
        WHERE t1.action_rank = 1 
    ),

    crm_classified AS ( -- コンタクト履歴に求職者情報を突合し、sfid/アクション/アクション日 の粒度でユニークに整理を行う/CRM用
        SELECT
            t2.*
            , t1.cd__c
            , t1.action
            , t1.created_date
            , CASE 
                WHEN t2.contact_date + 7 >= t2.step1 THEN 1 
                WHEN DATE_ADD(t2.contact_date , INTERVAL 3 MONTH) > t1.created_date THEN 2 
                ELSE 0 
            END AS crm_marketing_route
        FROM `tryt-bigquery-pj.marketing_edit_v2.01_09_01_before_exit_action_calc` AS t1 -- 出口発生月ベースにおける各種数値を集計するための処理を行ったテーブル
        LEFT JOIN entrance_history AS t_hist  
            ON t1.cd__c = t_hist.cd__c
        CROSS JOIN UNNEST(ARRAY(
            SELECT AS STRUCT h.contact_date, h.contact_month, h.entry_route, h.judge_entry_route, h.step1
            FROM UNNEST(t_hist.arr_history) AS h
            WHERE h.contact_date <= t1.created_date
                AND h.entry_route = 'CRM' 
                AND h.judge_entry_route LIKE '%再登録%'
                AND h.judge_entry_route NOT LIKE '%LINE%' 
                AND h.judge_entry_route NOT LIKE '%友人紹介%'
            ORDER BY h.contact_date DESC
            LIMIT 1
        )) AS t2
        WHERE t1.action_rank = 1
    ),

    nu_classified AS ( -- コンタクト履歴に求職者情報を突合し、sfid/アクション/アクション日 の粒度でユニークに整理を行う/NU用
        SELECT
            t2.*
            , t1.cd__c
            , t1.action
            , t1.created_date
            , CASE 
                WHEN t2.contact_date + 7 >= t2.step1 THEN 1 
                WHEN DATE_ADD(t2.contact_date , INTERVAL 3 MONTH) > t1.created_date THEN 2 
                ELSE 0 
            END AS nu_marketing_route
        FROM `tryt-bigquery-pj.marketing_edit_v2.01_09_01_before_exit_action_calc` AS t1 --出口発生月ベースにおける各種数値を集計するための処理を行ったテーブル 
        LEFT JOIN entrance_history AS t_hist
            ON t1.cd__c = t_hist.cd__c
        CROSS JOIN UNNEST(ARRAY(
            SELECT AS STRUCT h.contact_date, h.contact_month, h.entry_route, h.judge_entry_route, h.step1
            FROM UNNEST(t_hist.arr_history) AS h
            WHERE h.contact_date <= t1.created_date
                AND h.entry_route = 'NU' 
                AND h.contact_date IS NOT NULL
            ORDER BY h.contact_date DESC
            LIMIT 1
        )) AS t2
        WHERE t1.action_rank = 1
    ),

    route_judged AS ( -- ★★★各アクションに対して求職者情報を突合し、どの経路により当該のアクションに至ったかを「ラスト」で判定する
        SELECT
            t1.* EXCEPT(action_rank)
            , CASE 
                WHEN t1.created_date < 
                    CASE 
                        WHEN t2.marketing_route = 1 THEN t2.contact_date        --広告・SEO・通常CRMのレコード
                        WHEN t3.crm_marketing_route = 1 THEN t3.contact_date    --CRM再登録のレコード
                        WHEN t4.nu_marketing_route = 1 THEN t4.contact_date     --NUのレコード
                        WHEN t3.crm_marketing_route = 2 THEN t3.contact_date    --CRM再登録のレコード
                        WHEN t4.nu_marketing_route = 2 THEN t4.contact_date     --NUのレコード
                        ELSE GREATEST(IFNULL(t2.contact_date, DATE('1000-01-01')), IFNULL(t3.contact_date, DATE('1000-01-01')), IFNULL(t4.contact_date, DATE('1000-01-01'))) 
                    END 
                    THEN DATE('1000-01-01')
                ELSE 
                    CASE 
                        WHEN t2.marketing_route = 1 THEN t2.contact_month       --広告・SEO・通常CRMのレコード
                        WHEN t3.crm_marketing_route = 1 THEN t3.contact_month   --CRM再登録のレコード
                        WHEN t4.nu_marketing_route = 1 THEN t4.contact_month    --NUのレコード
                        WHEN t3.crm_marketing_route = 2 THEN t3.contact_month   --CRM再登録のレコード
                        WHEN t4.nu_marketing_route = 2 THEN t4.contact_month    --NUのレコード
                        ELSE GREATEST(IFNULL(t2.contact_month, DATE('1000-01-01')), IFNULL(t3.contact_month, DATE('1000-01-01')), IFNULL(t4.contact_month, DATE('1000-01-01'))) 
                    END 
            END AS contact_month1
            , CASE 
                WHEN t1.created_date < 
                    CASE 
                        WHEN t2.marketing_route = 1 THEN t2.contact_date        --広告・SEO・通常CRMのレコード
                        WHEN t3.crm_marketing_route = 1 THEN t3.contact_date    --CRM再登録のレコード
                        WHEN t4.nu_marketing_route = 1 THEN t4.contact_date     --NUのレコード
                        WHEN t3.crm_marketing_route = 2 THEN t3.contact_date    --CRM再登録のレコード
                        WHEN t4.nu_marketing_route = 2 THEN t4.contact_date     --NUのレコード
                        ELSE GREATEST(IFNULL(t2.contact_date, DATE('1000-01-01')), IFNULL(t3.contact_date, DATE('1000-01-01')), IFNULL(t4.contact_date, DATE('1000-01-01')))     
                    END 
                    THEN DATE('1000-01-01')
                ELSE 
                    CASE 
                        WHEN t2.marketing_route = 1 THEN t2.contact_date        --広告・SEO・通常CRMのレコード
                        WHEN t3.crm_marketing_route = 1 THEN t3.contact_date    --CRM再登録のレコード
                        WHEN t4.nu_marketing_route = 1 THEN t4.contact_date     --NUのレコード
                        WHEN t3.crm_marketing_route = 2 THEN t3.contact_date    --CRM再登録のレコード
                        WHEN t4.nu_marketing_route = 2 THEN t4.contact_date     --NUのレコード
                        ELSE GREATEST(IFNULL(t2.contact_date, DATE('1000-01-01')), IFNULL(t3.contact_date, DATE('1000-01-01')), IFNULL(t4.contact_date, DATE('1000-01-01')))     
                    END 
            END AS contact_date
            , CASE 
                WHEN t2.marketing_route = 1 THEN t2.entry_route --広告・SEO・通常CRMのレコード
                ELSE 'CRM' --★★★★★出口における経路分類に活用している(接触日から3ヵ月以内に計上されていればMK経由と判定し1のフラグが立つ、MK経由で無いと判定されたら"CRM"とする)★★★★★
            END AS entry_route
            , CASE 
                WHEN t2.marketing_route = 1 THEN t2.judge_entry_route           --広告・SEO・通常CRMのレコード
                WHEN t3.crm_marketing_route = 1 THEN t3.judge_entry_route       --CRM再登録のレコード
                WHEN t4.nu_marketing_route = 1 THEN 'NU経路'                    --NUのレコード
                WHEN t3.crm_marketing_route = 2 THEN t3.judge_entry_route       --CRM再登録のレコード
                WHEN t4.nu_marketing_route = 2 THEN 'NU経路'                    --NUのレコード
                ELSE '不明' 
            END AS judge_entry_route
        FROM `tryt-bigquery-pj.marketing_edit_v2.01_09_01_before_exit_action_calc`  AS t1 --出口発生月ベースにおける各種数値を集計するための処理を行ったテーブル
        LEFT JOIN normal_classified AS t2   --広告・SEO・通常CRMのレコード
            ON t1.cd__c = t2.cd__c
                AND t1.action = t2.action
                AND t1.created_date = t2.created_date
        LEFT JOIN crm_classified AS t3      --CRM再登録のレコード
            ON t1.cd__c = t3.cd__c
                AND t1.action = t3.action
                AND t1.created_date = t3.created_date
        LEFT JOIN nu_classified AS t4       --NUのレコード
            ON t1.cd__c = t4.cd__c
                AND t1.action = t4.action
                AND t1.created_date = t4.created_date
        WHERE t1.action_rank = 1 -- (PARTITION BY cd__c , DATE_TRUNC(created_date , MONTH) ORDER BY created_date ASC) により生成
        QUALIFY ROW_NUMBER() OVER
            (
                PARTITION BY t1.cd__c , t1.action_month , t1.action ORDER BY
                    CASE 
                        WHEN t1.created_date < 
                            CASE 
                                WHEN t2.marketing_route = 1 THEN t2.contact_date        --広告・SEO・通常CRMのレコード
                                WHEN t3.crm_marketing_route = 1 THEN t3.contact_date    --CRM再登録のレコード
                                WHEN t4.nu_marketing_route = 1 THEN t4.contact_date     --NUのレコード
                                WHEN t3.crm_marketing_route = 2 THEN t3.contact_date    --CRM再登録のレコード
                                WHEN t4.nu_marketing_route = 2 THEN t4.contact_date     --NUのレコード
                                ELSE GREATEST(IFNULL(t2.contact_date, DATE('1000-01-01')), IFNULL(t3.contact_date, DATE('1000-01-01')), IFNULL(t4.contact_date, DATE('1000-01-01')))  
                            END THEN DATE('1000-01-01')
                        ELSE 
                            CASE 
                                WHEN t2.marketing_route = 1 THEN t2.contact_date        --広告・SEO・通常CRMのレコード
                                WHEN t3.crm_marketing_route = 1 THEN t3.contact_date    --CRM再登録のレコード
                                WHEN t4.nu_marketing_route = 1 THEN t4.contact_date     --NUのレコード
                                WHEN t3.crm_marketing_route = 2 THEN t3.contact_date    --CRM再登録のレコード
                                WHEN t4.nu_marketing_route = 2 THEN t4.contact_date     --NUのレコード
                                ELSE GREATEST(IFNULL(t2.contact_date, DATE('1000-01-01')), IFNULL(t3.contact_date, DATE('1000-01-01')), IFNULL(t4.contact_date, DATE('1000-01-01')))     
                            END 
                    END DESC
            ) =1 -- 接触日が直近のレコードを優先させ、アクション月毎にユニークに集計 ★★★同月に何回同一アクションが発生してもカウントは1回とする★★★
        )

--最終集計
SELECT 
    *
FROM route_judged;
-- marketing_edit_v2.01_09_02_before_exit_route_judged



-- marketing_edit_v2.01_09_03_before_exit_analysis
    -- 更新日：2025/11/4
    -- 作業者：K.ISOZUMI
    -- 更新内容：営業日計算方法変更

/*
■実行内容
コンタクト履歴における各種アクションと売上請求管理や施工管理における成約情報(構造が異なる各種テーブルをユニオンしているだけのテーブル、PKはid_pseudo_exitとする)
*/

CREATE OR REPLACE TABLE `tryt-bigquery-pj.marketing_edit_v2.01_09_03_before_exit_analysis` CLUSTER BY occupation, entry_route AS -- 後続のBI向けにキーを設定する(251020)
WITH 
    exit_action AS ( -- 出口コンタクト履歴における各ステップ情報を引用
        SELECT
            id_pseudo_exit
            , cd__c
            , created_date
            , action_month
            , owner_id
            , action
            , step0_5
            , step1
            , step2
            , step3
            , step4
            , step5
            , record_date
            , branch                                                                        -- 20250612追加
            , sales_amount__c                                                               -- グロス売上
            , contact_month1
            , contact_date
            , entry_route
            , judge_entry_route
            , occupation
        FROM `tryt-bigquery-pj.marketing_edit_v2.01_09_02_before_exit_route_judged`
    ),

    contract_career AS ( -- 紹介事業における成約情報を引用
        SELECT
            CONCAT(id_invoice, '_', '成約数') AS id_pseudo_exit
            , cd__c
            , record_date AS created_date
            , record_month AS action_month
            , sales_name__c AS owner_id
            , '成約数' AS action
            , DATE(NULL) AS step0_5
            , DATE(NULL) AS step1
            , DATE(NULL) AS step2
            , DATE(NULL) AS step3
            , DATE(NULL) AS step4
            , DATE(NULL) AS step5
            , record_date
            , branch                                                                        -- 20250612追加
            , CAST(NULL AS INT64) AS sales_amount__c                                        -- グロス売上
            , contact_month AS contact_month1
            , contact_date
            , status AS entry_route
            , judge_entry_route_fixed AS judge_entry_route
            , occupation
        FROM `tryt-bigquery-pj.marketing_edit_v2.03_03_career_contract_processed`
        WHERE gross_flg = 1
            AND contract_count = 1
    ),

    gross_sales_career AS ( -- 紹介事業におけるグロス売上情報を引用
        SELECT
            CONCAT(id_invoice, '_', 'グロス売上') AS id_pseudo_exit
            , cd__c
            , record_date AS created_date
            , record_month AS action_month
            , sales_name__c AS owner_id
            , 'グロス売上' AS action
            , DATE(NULL) AS step0_5
            , DATE(NULL) AS step1
            , DATE(NULL) AS step2
            , DATE(NULL) AS step3
            , DATE(NULL) AS step4
            , DATE(NULL) AS step5
            , record_date
            , branch                                                                        -- 20250612追加
            , sales_amount__c                                                               -- グロス売上
            , contact_month AS contact_month1
            , contact_date
            , status AS entry_route
            , judge_entry_route_fixed AS judge_entry_route
            , occupation
        FROM `tryt-bigquery-pj.marketing_edit_v2.03_03_career_contract_processed`
        WHERE gross_flg = 1
    ),

    net_sales_career AS ( -- 紹介事業における純契約売上情報を引用
        SELECT
            CONCAT(id_invoice, '_', '純契約売上') AS id_pseudo_exit
            , cd__c
            , record_date AS created_date
            , record_month AS action_month
            , sales_name__c AS owner_id
            , '純契約売上' AS action
            , DATE(NULL) AS step0_5
            , DATE(NULL) AS step1
            , DATE(NULL) AS step2
            , DATE(NULL) AS step3
            , DATE(NULL) AS step4
            , DATE(NULL) AS step5
            , record_date
            , branch                                                                        -- 20250612追加
            , sales_amount__c                                                               -- 純契約売上
            , contact_month AS contact_month1
            , contact_date
            , status AS entry_route
            , judge_entry_route_fixed AS judge_entry_route
            , occupation
        FROM `tryt-bigquery-pj.marketing_edit_v2.03_03_career_contract_processed`
    ),

    contract_const AS ( -- 施工管理における成約情報を引用
        SELECT
            CONCAT(id_invoice, '_', '【建設】成約数') AS id_pseudo_exit 
            , cd__c
            , record_date AS created_date
            , record_month AS action_month
            , owner_id
            , '成約数' AS action
            , DATE(NULL) AS step0_5
            , DATE(NULL) AS step1
            , DATE(NULL) AS step2
            , DATE(NULL) AS step3
            , DATE(NULL) AS step4
            , DATE(NULL) AS step5
            , record_date
            , branch                                                                        -- 20250612追加
            , CAST(NULL AS INT64) AS sales_amount__c                                        
            , contact_month AS contact_month1
            , contact_date
            , status AS entry_route
            , judge_entry_route_fixed AS judge_entry_route
            , occupation
        FROM `tryt-bigquery-pj.marketing_edit_v2.03_04_const_contract_processed`
    ),

    amount_const AS ( -- 施工管理における累計売上情報を引用
        SELECT
            CONCAT(id_invoice, '_', '【建設】累計売上') AS id_pseudo_exit 
            , cd__c
            , record_date AS created_date
            , record_month AS action_month
            , owner_id
            , '【建設】累計売上' AS action
            , DATE(NULL) AS step0_5
            , DATE(NULL) AS step1
            , DATE(NULL) AS step2
            , DATE(NULL) AS step3
            , DATE(NULL) AS step4
            , DATE(NULL) AS step5
            , record_date
            , branch                                                                        -- 20250612追加
            , total_amount AS sales_amount__c                                               -- 売上額 (SUM(t1.seikyukingaku * t1.kikan) OVER(PARTITION BY t1.staffCD) により集計)
            , contact_month AS contact_month1
            , contact_date
            , status AS entry_route
            , judge_entry_route_fixed AS judge_entry_route
            , occupation
        FROM `tryt-bigquery-pj.marketing_edit_v2.03_04_const_contract_processed`
    ),

    step_invoice_integrated AS ( -- コンタクト履歴由来のレコードと売上請求管理由来のレコードをユニオン
        SELECT * FROM exit_action 
        UNION ALL
        SELECT * FROM contract_career 
        UNION ALL
        SELECT * FROM gross_sales_career 
        UNION ALL
        SELECT * FROM net_sales_career 
        UNION ALL
        SELECT * FROM contract_const 
        UNION ALL
        SELECT * FROM amount_const
    ),

    workday_ajs AS ( -- リードタイム計算用に営業日を突合
        SELECT
            t1.*
            , CASE 
                WHEN t1.created_date IS NULL THEN NULL
                WHEN t1.action_month = DATE_TRUNC(t1.created_date , MONTH) THEN t2.workday_calculation_thismonth_1 
                WHEN DATE_ADD(t1.action_month , INTERVAL 1 MONTH) = DATE_TRUNC(t1.created_date , MONTH) THEN t2.workday_calculation_lastmonth_1
                ELSE NULL 
            END AS action_workday -- アクション営業日
        FROM step_invoice_integrated AS t1
        LEFT JOIN 
            (
                SELECT
                    calendar_date
                    , workday_calculation_thismonth_1
                    , workday_calculation_lastmonth_1
                FROM `tryt-bigquery-pj.production_tryt.master_workday` -- 営業日マスタ https://docs.google.com/spreadsheets/d/1se4E_tSOTM50Td9WsTmpYhpLd3_CIYQMjYT36uupTVc/edit?gid=1687421902#gid=1687421902
                WHERE calendar_date <= CURRENT_DATE('Asia/Tokyo')
            ) t2
            ON t1.created_date = t2.calendar_date
    )

--最終集計
SELECT 
    *
FROM workday_ajs;
-- marketing_edit_v2.01_09_03_before_exit_analysis
