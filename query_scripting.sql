WITH RekapTransaksi AS (
    SELECT 
        id_nasabah,
        COUNT(id_transaksi) AS total_frekuensi_transaksi,
        SUM(nominal) AS total_nominal_transaksi
    FROM "public"."raw_transaksi_harian"
    GROUP BY id_nasabah
),
RekapTiket AS (
    SELECT 
        id_nasabah,
        COUNT(id_tiket) AS total_kendala,
        SUM(CASE WHEN status_tiket = 'Proses (Open)' THEN 1 ELSE 0 END) AS tiket_masih_open
    FROM "public"."raw_tiket_bantuan"
    GROUP BY id_nasabah
),
DataGabungan AS (
    SELECT 
        n.id_nasabah,
        n.nama_lengkap,
        n.tipe_nasabah,
        COALESCE(tr.total_frekuensi_transaksi, 0) AS total_transaksi,
        COALESCE(tr.total_nominal_transaksi, 0) AS total_nominal,
        COALESCE(tk.total_kendala, 0) AS total_kendala_dilaporkan,
        COALESCE(tk.tiket_masih_open, 0) AS tiket_belum_selesai,
        CASE 
            WHEN n.tipe_nasabah IN ('VIP', 'Premium') AND COALESCE(tk.tiket_masih_open, 0) > 0 
                THEN 'URGENT - Prioritas CS'
            WHEN COALESCE(tk.tiket_masih_open, 0) > 0 
                THEN 'Warning - Perlu Follow Up'
            ELSE 'Aman - Tidak Ada Kendala'
        END AS status_perhatian_cs
    FROM "public"."raw_nasabah" n
    LEFT JOIN RekapTransaksi tr ON n.id_nasabah = tr.id_nasabah
    LEFT JOIN RekapTiket tk ON n.id_nasabah = tk.id_nasabah
)
SELECT * 
FROM DataGabungan
ORDER BY 
    CASE WHEN status_perhatian_cs = 'URGENT - Prioritas CS' THEN 1 
         WHEN status_perhatian_cs = 'Warning - Perlu Follow Up' THEN 2 
         ELSE 3 END,
    total_nominal DESC;




WITH GabunganData AS (
    SELECT 
        l.client_id,
        (COALESCE(l."General/Other_amount_sum", 0) + COALESCE(l."Household/Utilities_amount_sum", 0)) AS total_pengeluaran,
        cr.loan_risk_label,
        dr.digital_risk_segment
    FROM "node_6256192d_FLOW_datamart_lifestyle_analytics" l
    LEFT JOIN "node_6256192d_FLOW_datamart_credit_risk" cr ON l.client_id = cr.client_id
    LEFT JOIN "node_6256192d_FLOW_datamart_digital_risk" dr ON l.client_id = dr.client_id
),
MesinSkoring AS (
    SELECT 
        *,
        CASE WHEN loan_risk_label = 'Good Loan (Lancar)' THEN 1 ELSE 0 END AS poin_kredit,
        CASE WHEN digital_risk_segment = 'Digital User - Prime (Aman)' THEN 1 ELSE 0 END AS poin_digital,
        CASE WHEN total_pengeluaran > 100000 THEN 1 ELSE 0 END AS poin_pengeluaran
    FROM GabunganData
)
SELECT 
    client_id,
    total_pengeluaran,
    loan_risk_label,
    digital_risk_segment,
    (poin_kredit + poin_digital + poin_pengeluaran) AS total_skor,
    CASE 
        WHEN (poin_kredit + poin_digital + poin_pengeluaran) = 3 THEN 'Approved - Platinum Card'
        WHEN (poin_kredit + poin_digital + poin_pengeluaran) = 2 THEN 'Review - Gold Card'
        ELSE 'Rejected - Basic / No Card'
    END AS keputusan_final
FROM MesinSkoring
ORDER BY total_skor DESC, total_pengeluaran DESC;





WITH MarketingLeads AS (
    SELECT 
        client_id,
        nama_konsumen,
        estimated_age,
        rekomendasi_kampanye,
        rata_rata_saldo,
        loan_id 
    FROM "node_6256192d_FLOW_datamart_top_leads_telemarketing"
),

CreditWarnings AS (
    SELECT 
        loan_id,
        "Total_Pinjaman" AS total_pinjaman,
        "status_Pinjaman" AS status_pinjaman
    FROM "node_6256192d_FLOW_datamart_credit_warning"
)
SELECT 
    m.client_id,
    m.nama_konsumen,
    m.rekomendasi_kampanye,
    m.rata_rata_saldo,
    COALESCE(cw.status_pinjaman, 'TIDAK ADA PINJAMAN AKTIF') AS status_kredit_saat_ini,
    CASE 
        WHEN m.rekomendasi_kampanye LIKE '%KPR%' AND cw.status_pinjaman NOT IN ('A', 'C') THEN 'BATALKAN PENAWARAN (RISIKO TINGGI)'
        WHEN m.rekomendasi_kampanye LIKE '%Investasi%' AND cw.status_pinjaman IN ('A', 'C') THEN 'UPSELL: Tawarkan Layanan Prioritas'
        WHEN m.rekomendasi_kampanye LIKE '%KPR%' THEN 'LANJUTKAN PENAWARAN KPR'
        ELSE 'Kampanye Reguler'
    END AS final_marketing_action
FROM MarketingLeads m
LEFT JOIN CreditWarnings cw ON m.loan_id = cw.loan_id
ORDER BY m.rata_rata_saldo DESC;




WITH DataPinjaman AS (
    SELECT 
        loan_id, 
        account_id, 
        amount AS loan_amount, 
        duration AS loan_duration_months, 
        status,
        CASE
            WHEN status IN ('A', 'C') THEN 'Good Loan (Lancar)'
            WHEN status IN ('B', 'D') THEN 'Bad Loan (Macet)'
            ELSE 'Unknown'
        END AS loan_risk_label
    FROM "public"."raw_loan"
),


PemilikAkun AS (
    SELECT 
        account_id, 
        client_id
    FROM "public"."raw_disp"
    WHERE type = 'OWNER'
),
ProfilNasabah AS (
    SELECT 
        client_id, 
        district_id, 
        gender,
        EXTRACT(YEAR FROM CAST(birth_date AS DATE)) AS birth_year
    FROM "public"."raw_client"
),
EkonomiDaerah AS (
    SELECT 
        district_id, 
        district_name, 
        average_salary, 
        unemployment_rate_95
    FROM "public"."raw_district"
),
PerilakuAkun AS (
    SELECT 
        account_id, 
        frequency AS statement_frequency
    FROM "public"."raw_account"
)
SELECT 
    dp.loan_id,
    dp.loan_risk_label,
    dp.loan_amount,
    dp.loan_duration_months,
    pn.gender,
    (2026 - pn.birth_year) AS current_age,
    ed.district_name,
    ed.average_salary AS district_avg_salary,
    ed.unemployment_rate_95 AS district_unemployment_rate,
    pa.statement_frequency
FROM DataPinjaman dp
INNER JOIN PemilikAkun pa_owner ON dp.account_id = pa_owner.account_id
INNER JOIN ProfilNasabah pn ON pa_owner.client_id = pn.client_id
INNER JOIN EkonomiDaerah ed ON pn.district_id = ed.district_id
INNER JOIN PerilakuAkun pa ON dp.account_id = pa.account_id
ORDER BY dp.loan_amount DESC;




WITH TransaksiPengeluaran AS (
    SELECT 
        d.client_id,
        t.amount,
        
        CASE 
            WHEN t.k_symbol = 'SIPO' THEN 'Household/Utilities'
            WHEN t.k_symbol = 'UVER' THEN 'Loan Repayment'
            WHEN t.k_symbol = 'POJISTNE' THEN 'Insurance Premium'
            WHEN t.k_symbol = 'SANKC. UROK' THEN 'Sanction/Penalty'
            WHEN t.k_symbol IS NULL OR t.k_symbol = '' THEN 'General/Other'
            ELSE t.k_symbol 
        END AS spending_category
    FROM "public"."raw_trans" t
    INNER JOIN "public"."raw_disp" d ON t.account_id = d.account_id
    WHERE d.type = 'OWNER' AND t.type = 'VYDAJ' 
)
SELECT 
    client_id,
    spending_category,
    SUM(amount) AS total_spent
FROM TransaksiPengeluaran
GROUP BY client_id, spending_category
ORDER BY client_id, total_spent DESC;



WITH AppStats AS (
    SELECT 
        client_id,
        COUNT(activity_id) AS total_app_interactions,
        MAX(timestamp) AS last_activity_date
    FROM "public"."raw_app_activity"
    GROUP BY client_id
),
CreditScore AS (
    SELECT 
        client_id,
        credit_score
    FROM "public"."raw_external_credit_score"
)
SELECT 
    c.client_id,
    c.gender,
    c.birth_date,
    COALESCE(a.total_app_interactions, 0) AS total_app_interactions,
    a.last_activity_date,
    cs.credit_score,
    CASE 
        WHEN a.total_app_interactions > 0 AND cs.credit_score >= 600 THEN 'Digital User - Prime (Aman)'
        WHEN a.total_app_interactions > 0 AND cs.credit_score < 600 THEN 'Digital User - Subprime (Beresiko)'
        WHEN a.total_app_interactions IS NULL THEN 'Traditional User (Tidak Pakai App)'
        ELSE 'Uncategorized'
    END AS digital_risk_segment
FROM "public"."raw_client" c
LEFT JOIN AppStats a ON c.client_id = a.client_id
LEFT JOIN CreditScore cs ON c.client_id = cs.client_id
ORDER BY total_app_interactions DESC;



WITH ProfilDemografi AS (
    SELECT 
        client_id,
        nama_konsumen,
        estimated_age,
        region_name,
        unemployment_risk_rank
    FROM "node_6256192d_FLOW_datamart_client_profile"
    WHERE account_role = 'OWNER'
),
KekuatanFinansial AS (
    SELECT 
        client_id,
        rata_rata_saldo,
        total_uang_masuk
    FROM "node_6256192d_FLOW_datamart_loan_360"
)
SELECT 
    d.client_id,
    d.nama_konsumen,
    d.estimated_age,
    d.region_name,
    f.rata_rata_saldo,
    CASE 
        WHEN d.estimated_age >= 50 AND f.rata_rata_saldo > 40000 THEN 'Prioritas: Investasi Pensiun'
        WHEN d.estimated_age BETWEEN 25 AND 49 AND f.rata_rata_saldo > 50000 THEN 'Prioritas: Penawaran KPR'
        ELSE 'Reguler: Kartu Kredit / KTA'
    END AS rekomendasi_kampanye
FROM ProfilDemografi d
INNER JOIN KekuatanFinansial f ON d.client_id = f.client_id
ORDER BY f.rata_rata_saldo DESC;



WITH ExtractData AS (
    SELECT
        client_id,
        nama_konsumen,
        type AS account_role,
        "A2" AS district_name,
        "A3" AS region_name,
        "A12" AS unemployment_rate_95,
        '19' || SUBSTRING(birth_number::text FROM 1 FOR 2) AS birth_year
    FROM "public"."dim_konsumen"
),
AgeCaculation AS (
    SELECT
        *,
        (1999 - birth_year::integer) AS estimated_age
    FROM ExtractData
)
SELECT
    client_id,
    nama_konsumen,
    account_role,
    district_name,
    region_name,
    unemployment_rate_95,
    DENSE_RANK() OVER(PARTITION BY region_name ORDER BY unemployment_rate_95 DESC) AS unemployment_risk_rank
FROM AgeCaculation
ORDER BY region_name, unemployment_risk_rank;




WITH STG_Active_Loans AS (
    SELECT
        account_id,
        loan_id,
        amount AS total_pinjaman,
        status As status_pinjaman
    FROM raw_loan
    WHERE status IN ('C', 'D')
),
STG_Card_Holders AS (
    SELECT
        d.account_id,
        c.card_id,
        c.type AS Jenis_Kartu
    FROM raw_card c
    INNER JOIN raw_disp d 
    ON c.disp_id = d.disp_id
    WHERE d.type = 'OWNER'
)
SELECT
    l.account_id,
    l.loan_id,
    c.card_id,
    c.Jenis_Kartu,
    l.total_pinjaman,
    l.status_pinjaman
FROM STG_Active_Loans l 
INNER JOIN STG_Card_Holders c
ON l.account_id = c.account_id
ORDER BY total_pinjaman ASC;



WITH district_summary AS (
    SELECT
        region,
        district_name,
        COUNT(client_id) AS total_nasabah,
        SUM(bad_debt_flag) AS total_macet
    FROM "node_6256192d_FLOW_risk_features_prep"
    GROUP BY region, district_name
),
ranked_district AS (
    SELECT
        region,
        district_name,
        total_nasabah,
        total_macet,
        ROW_NUMBER() OVER(PARTITION BY region ORDER BY total_macet DESC) as ranking_macet
    FROM district_summary
)
SELECT *
FROM ranked_district
WHERE ranking_macet <= 3;