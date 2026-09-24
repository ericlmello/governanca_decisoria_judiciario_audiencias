/*
 * RASCUNHO — Audiências realizadas (Efetiva/Adiada) segundo os novos critérios
 * do documento "PAI - Critérios Audiências SETIC".
 *
 * NÃO EXECUTAR EM PRODUÇÃO ainda: todo trecho marcado com
 * `-- TODO(confirmar)` depende de valores (id_tipo_audiencia, id_evento,
 * cálculo de dias úteis) que não puderam ser verificados contra a base
 * pje_1grau_cds (sem acesso de rede a 10.2.36.13:3032 nesta sessão).
 *
 * Ver docs/analise_criterios_audiencias_setic.md para o comparativo completo
 * com a query original (sql/audiencias_realizadas_original.sql).
 *
 * Regras implementadas (ver seção 2 do doc de análise):
 *   1. Regra geral: redesignação de audiência da MESMA categoria -> ADIADA.
 *   2. Inicial: qualquer audiência subsequente (UNA/Instrução/Encerramento de
 *      Instrução/Julgamento) -> EFETIVA.
 *   3. UNA: bipartição (Instrução designada) -> ADIADA por padrão, exceto:
 *        a) diligência + Encerramento de Instrução em até 3 dias úteis -> EFETIVA
 *        b) sem diligência + Julgamento (ou conclusão/prolação sentença/
 *           homologação de acordo) em até 3 dias úteis -> EFETIVA
 *   4. Instrução: diligência + Encerramento de Instrução -> EFETIVA;
 *      sem diligência + Julgamento -> EFETIVA.
 *   5. Perícia ativa com prazo VENCIDO não é tratada aqui (regra pertence ao
 *      painel de perícias do PAI — dependência externa, fora de escopo).
 */

-- TODO(confirmar): ids reais em pje.tb_tipo_audiencia (rodar query 4.1 do doc de análise)
-- Valores abaixo são placeholders de nome, não de id numérico.
-- id_tipo_audiencia:
--   :TIPO_INICIAL
--   :TIPO_UNA
--   :TIPO_INSTRUCAO
--   :TIPO_ENCERRAMENTO_INSTRUCAO
--   :TIPO_JULGAMENTO   (a query original usa o id 4 para este tipo — confirmar)

WITH audiencias_realizadas AS (
    SELECT tp.id_processo,
        tpa.id_processo_trf AS num_proc_id_origem,
        tpa.id_processo_audiencia,
        tpa.dt_inicio dta_audiencia,
        tp.nr_processo,
        toj.id_orgao_julgador,
        tul.ds_nome AS magistrado,
        tpa.id_tipo_audiencia,
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
        -- TODO(confirmar): excluir também Encerramento de Instrução da população avaliada,
        -- como já é feito para Julgamento (tipo 4)? O documento não trata essas duas como
        -- audiências cuja efetividade é medida, apenas como "sinais" de outras audiências.
        AND tpa.id_tipo_audiencia NOT IN (4 /* Julgamento */ /*, :TIPO_ENCERRAMENTO_INSTRUCAO */)
        AND tpt.cd_processo_status = 'D'
        AND date_trunc('day', tpa.dt_inicio) > '${VAR_ULT_DT_AUDIENCIA}'
        -- TODO(confirmar): buffer de segurança recalculado para 3 dias ÚTEIS (não 5 corridos)
        -- assim que houver função/tabela de dias úteis disponível no schema.
        and date_trunc('day', tpa.dt_fim) <= date_trunc('day', current_date - 6)
),

-- Próxima audiência (de qualquer tipo) designada para o mesmo processo após a atual.
proxima_audiencia AS (
    SELECT
        r.id_processo_audiencia,
        r.id_tipo_audiencia AS id_tipo_audiencia_origem,
        tpa2.id_tipo_audiencia AS id_tipo_audiencia_proxima,
        tpa2.dt_marcacao
    FROM audiencias_realizadas r
    LEFT JOIN LATERAL (
        SELECT tpa2.id_tipo_audiencia, tpa2.dt_marcacao
        FROM pje.tb_processo_audiencia tpa2
        WHERE tpa2.id_processo_trf = r.num_proc_id_origem
          AND tpa2.dt_marcacao > r.dta_audiencia
        ORDER BY tpa2.dt_marcacao ASC
        LIMIT 1
    ) tpa2 ON TRUE
),

-- Movimentos de diligência (perícia ativa, ofício, carta precatória, mandado)
-- em até 3 dias úteis após a audiência.
-- TODO(confirmar): ids/ds_caminho_completo reais (rodar query 4.2 do doc de análise)
-- e função de "N dias úteis a partir de uma data" (placeholder: fn_soma_dias_uteis).
movimentos_diligencia AS (
    SELECT DISTINCT r.id_processo_audiencia
    FROM audiencias_realizadas r
    INNER JOIN pje.tb_processo_evento tpe ON tpe.id_processo = r.num_proc_id_origem
    INNER JOIN pje.tb_evento e ON e.id_evento = tpe.id_evento
    WHERE tpe.dt_atualizacao BETWEEN date_trunc('day', r.dta_audiencia::date)
        AND fn_soma_dias_uteis(r.dta_audiencia::date, 3) -- TODO(confirmar): função de dias úteis
        AND (
            e.ds_evento ILIKE '%perícia%'          -- TODO(confirmar): + condição de laudo em aberto/prazo válido
            OR e.ds_evento ILIKE '%expedição de ofício%'
            OR e.ds_evento ILIKE '%expedição de carta precatória%'
            OR e.ds_evento ILIKE '%expedição de mandado%'
        )
),

-- Movimentos de encerramento (conclusão/prolação de sentença, homologação de
-- acordo, marcação de julgamento) em até 3 dias úteis.
movimentos_julgamento AS (
    SELECT DISTINCT r.id_processo_audiencia
    FROM audiencias_realizadas r
    LEFT JOIN pje.tb_processo_evento tpe ON tpe.id_processo = r.num_proc_id_origem
        AND tpe.dt_atualizacao BETWEEN date_trunc('day', r.dta_audiencia::date)
            AND fn_soma_dias_uteis(r.dta_audiencia::date, 3) -- TODO(confirmar)
        AND (
            tpe.ds_texto_final_externo ILIKE 'Conclusos%sentença%'
            OR tpe.ds_evento ILIKE '%prolação%sentença%'
            OR tpe.ds_evento ILIKE '%homologação%acordo%'
        )
    LEFT JOIN proxima_audiencia pa ON pa.id_processo_audiencia = r.id_processo_audiencia
        AND pa.id_tipo_audiencia_proxima = 4 -- Julgamento; TODO(confirmar) id real
        AND pa.dt_marcacao <= fn_soma_dias_uteis(r.dta_audiencia::date, 3)
    WHERE tpe.id_processo IS NOT NULL OR pa.id_processo_audiencia IS NOT NULL
),

classificacao AS (
    SELECT
        r.*,
        CASE
            -- 1) Regra geral: redesignação da mesma categoria
            WHEN pa.id_tipo_audiencia_proxima = r.id_tipo_audiencia_origem THEN 'Adiada'

            -- 2) Audiência Inicial: qualquer subsequente conta como efetiva
            WHEN r.id_tipo_audiencia /* = :TIPO_INICIAL */ = 1 -- TODO(confirmar) id real de "Inicial"
                 AND pa.id_tipo_audiencia_proxima IS NOT NULL THEN 'Efetiva'

            -- 3) UNA -> Instrução (bipartição)
            WHEN r.id_tipo_audiencia /* = :TIPO_UNA */ = 2 -- TODO(confirmar) id real de "UNA"
                 AND pa.id_tipo_audiencia_proxima /* = :TIPO_INSTRUCAO */ = 3 -- TODO(confirmar)
                 AND md.id_processo_audiencia IS NOT NULL
                 -- TODO(confirmar): também exigir Encerramento de Instrução designado
                 THEN 'Efetiva'
            WHEN r.id_tipo_audiencia = 2 -- UNA, TODO(confirmar)
                 AND pa.id_tipo_audiencia_proxima = 3 -- Instrução, TODO(confirmar)
                 AND md.id_processo_audiencia IS NULL
                 AND mj.id_processo_audiencia IS NOT NULL THEN 'Efetiva'
            WHEN r.id_tipo_audiencia = 2 -- UNA
                 AND pa.id_tipo_audiencia_proxima = 3 -- Instrução
                 THEN 'Adiada' -- bipartição injustificada

            -- 4) Instrução
            WHEN r.id_tipo_audiencia = 3 -- Instrução, TODO(confirmar)
                 AND md.id_processo_audiencia IS NOT NULL
                 -- TODO(confirmar): exigir Encerramento de Instrução designado
                 THEN 'Efetiva'
            WHEN r.id_tipo_audiencia = 3 -- Instrução
                 AND md.id_processo_audiencia IS NULL
                 AND mj.id_processo_audiencia IS NOT NULL THEN 'Efetiva'

            ELSE 'Adiada'
        END AS status
    FROM audiencias_realizadas r
    LEFT JOIN proxima_audiencia pa ON pa.id_processo_audiencia = r.id_processo_audiencia
    LEFT JOIN movimentos_diligencia md ON md.id_processo_audiencia = r.id_processo_audiencia
    LEFT JOIN movimentos_julgamento mj ON mj.id_processo_audiencia = r.id_processo_audiencia
)
SELECT
    nr_processo, id_processo,
    id_orgao_julgador,
    dta_audiencia dt_audiencia,
    replace(ds_tipo_audiencia, ' por videoconferência', '') tipo_audiencia,
    case
        when STRPOS(ds_tipo_audiencia, ' por videoconferência') > 0 then
            'Videoconferência'
        else
            'Presencial'
    end modalidade,
    ds_classe_judicial,
    magistrado,
    status,
    fase,
    NULL::date AS dt_ult_mov,
    TO_CHAR(CURRENT_DATE, 'YYYY-MM-DD') AS dta_ref
FROM classificacao;
