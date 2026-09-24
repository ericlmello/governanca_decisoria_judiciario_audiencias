/*
 * Audiências realizadas (efetivas e adiadas) + Pauta programada
 * scripts adaptados da SETIC
 * *** OBS: pauta programada, que está no último UNION, roda no DW_TRT!! 10.2.2.66:1036
 *
 * Versão original (baseline), mantida aqui como referência para comparação com a
 * versão revisada (audiencias_realizadas_v2_draft.sql) que implementa os novos
 * critérios do documento "PAI - Critérios Audiências SETIC".
 * Ver docs/analise_criterios_audiencias_setic.md para o comparativo detalhado.
 */

-- REALIZADAS:

WITH audiencias_realizadas AS (
    SELECT tp.id_processo,
        tpa.id_processo_trf AS num_proc_id_origem,
        tpa.id_processo_audiencia,
        tpa.dt_inicio dta_audiencia,
        tp.nr_processo,
        toj.id_orgao_julgador,
        tul.ds_nome AS magistrado,
        tta.ds_tipo_audiencia,
        c.ds_classe_judicial,
        fase.nm_agrupamento_fase fase,
        null as dt_ult_mov
    FROM
        tb_processo_audiencia tpa
    INNER JOIN
        pje.tb_tipo_audiencia tta ON tpa.id_tipo_audiencia = tta.id_tipo_audiencia
    INNER JOIN
        pje.tb_processo_trf tpt ON tpt.id_processo_trf = tpa.id_processo_trf
    INNER JOIN
        pje.tb_processo tp ON tp.id_processo = tpt.id_processo_trf
    INNER JOIN
        pje.tb_sala_fisica ts ON ts.id_sala_fisica = tpa.id_sala_fisica
    INNER JOIN
        pje.tb_orgao_julgador toj ON toj.id_orgao_julgador = ts.id_orgao_julgador
    INNER JOIN
        pje.tb_usuario_login tul ON tul.id_usuario = tpa.id_pessoa_realizador
    inner join tb_classe_judicial c
        on c.id_classe_judicial = tpt.id_classe_judicial
    inner join tb_agrupamento_fase fase
        on fase.id_agrupamento_fase = tp.id_agrupamento_fase
        and fase.in_ativo = 'S'
    WHERE
        tpa.cd_status_audiencia = 'F'
        AND tpa.id_tipo_audiencia <> 4
        AND tpt.cd_processo_status = 'D'
        AND date_trunc('day', tpa.dt_inicio) > '${VAR_ULT_DT_AUDIENCIA}'
        and date_trunc('day', tpa.dt_fim) <= date_trunc('day', current_date-6)
),

audiencias_adiadas AS (
    SELECT *
    FROM audiencias_realizadas r
    WHERE
        NOT EXISTS (
            SELECT 1
            FROM pje.tb_processo_evento tpe
            INNER JOIN pje.tb_evento e ON e.id_evento = tpe.id_evento
            WHERE
                tpe.id_processo = r.num_proc_id_origem
                AND tpe.dt_atualizacao BETWEEN date_trunc('day', r.dta_audiencia::date) AND r.dta_audiencia::date + INTERVAL '5' DAY
                AND (
                    tpe.ds_texto_final_externo ILIKE 'Conclusos%sentença%'
                    OR e.ds_caminho_completo ILIKE 'Magistrado|Julgamento%'
                    OR e.id_evento IN (941, 371)
                )
        )
        AND
        NOT EXISTS (
            SELECT 1
            FROM pje.tb_processo_audiencia tpa2
            WHERE
                tpa2.id_processo_trf = r.num_proc_id_origem
                AND tpa2.dt_marcacao BETWEEN date_trunc('day', r.dta_audiencia::date)
                AND r.dta_audiencia::date + INTERVAL '5' DAY
                AND tpa2.id_tipo_audiencia = 4
        )
),
audiencias_encerradas AS (
    SELECT *
    FROM audiencias_realizadas ar
    WHERE id_processo_audiencia NOT IN (
        SELECT aa.id_processo_audiencia
        FROM audiencias_adiadas aa
        WHERE aa.id_processo_audiencia = ar.id_processo_audiencia
    )
)
SELECT
    ae.nr_processo, ae.id_processo,
    ae.id_orgao_julgador,
    ae.dta_audiencia dt_audiencia,
    replace(ae.ds_tipo_audiencia, ' por videoconferência', '') tipo_audiencia,
    case
        when STRPOS(ae.ds_tipo_audiencia, ' por videoconferência') > 0 then
            'Videoconferência'
        else
            'Presencial'
    end modalidade,
    ae.ds_classe_judicial,
    ae.magistrado,
    'Efetiva' AS status,
    ae.fase,
    NULL::date AS dt_ult_mov,
    TO_CHAR(CURRENT_DATE, 'YYYY-MM-DD') AS dta_ref
FROM
    audiencias_encerradas ae

UNION ALL

SELECT
    aa.nr_processo, aa.id_processo,
    aa.id_orgao_julgador,
    aa.dta_audiencia dt_audiencia,
    replace(aa.ds_tipo_audiencia, ' por videoconferência', '') tipo_audiencia,
    case
        when STRPOS(aa.ds_tipo_audiencia, ' por videoconferência') > 0 then
            'Videoconferência'
        else
            'Presencial'
    end modalidade,
    aa.ds_classe_judicial,
    aa.magistrado,
    'Adiada' AS status,
    aa.fase,
    NULL::date AS dt_ult_mov,
    TO_CHAR(CURRENT_DATE, 'YYYY-MM-DD') AS dta_ref
FROM
    audiencias_adiadas aa
