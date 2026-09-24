/*
 * RASCUNHO — Audiências realizadas (Efetiva/Adiada) segundo os novos critérios
 * do documento "PAI - Critérios Audiências SETIC".
 *
 * NÃO EXECUTAR EM PRODUÇÃO ainda: pontos marcados com `-- TODO(confirmar)` ou
 * `-- TODO(decisão)` seguem pendentes. Ver docs/analise_criterios_audiencias_setic.md
 * para o comparativo completo com a query original (sql/audiencias_realizadas_original.sql).
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
 *
 * Mapeamento de pje.tb_tipo_audiencia confirmado pelo usuário (36 tipos cadastrados):
 *   Inicial ..................... 3, 16 (sumaríssimo), 22 (videoconf), 29 (videoconf sumaríssimo)
 *   UNA .......................... 5, 19 (sumaríssimo), 23 (videoconf), 31 (videoconf sumaríssimo)
 *   Instrução .................... 6, 12 (sumaríssimo), 24 (videoconf), 27 (videoconf sumaríssimo)
 *   Encerramento de Instrução .... 10, 25 (videoconf)
 *   Julgamento ................... 4
 *
 * TODO(decisão) — tipos que o documento NÃO define regra explícita para, e que por isso
 * são marcados como status = 'Não classificado' em vez de um chute de Efetiva/Adiada:
 *   - 8  Instrução e Julgamento (audiência única que já conclui com julgamento — é uma
 *        variante de Instrução, ou deve ter regra própria já que não depende de sinal
 *        posterior?)
 *   - 7  UNA-RS ou Justificação Prévia / 9 Una - RS (o que significa "RS" aqui? variante
 *        de UNA ou outra coisa?)
 *   - Totalmente fora do documento: Conciliação em Conhecimento (1, 32, 20, 33),
 *     Conciliação em Execução (2, 34, 36, 21, 35, 37), Inquirição de testemunha —
 *     juízo deprecado (11, 26), Justificação Prévia (18), Mediação (13, 14, 15, 28),
 *     Pública (17, 30). Ficam fora da população avaliada (WHERE) até decisão do usuário
 *     sobre se entram e com qual regra.
 */

WITH parametros AS (
    SELECT
        ARRAY[3, 16, 22, 29]   AS tipo_inicial,
        ARRAY[5, 19, 23, 31]   AS tipo_una,
        ARRAY[6, 12, 24, 27]   AS tipo_instrucao,
        ARRAY[10, 25]          AS tipo_encerramento_instrucao,
        ARRAY[4]               AS tipo_julgamento
),

audiencias_realizadas AS (
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
    CROSS JOIN parametros p
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
        -- População avaliada = só os tipos com regra definida no documento (Inicial/UNA/
        -- Instrução). Encerramento de Instrução e Julgamento são "sinais", não audiências
        -- cuja efetividade é medida (mesmo raciocínio da query original, que excluía só o
        -- tipo 4). Os tipos ambíguos/fora do documento (ver TODO(decisão) acima) ficam de
        -- fora por ora — inclua-os aqui quando a regra deles for definida.
        AND tpa.id_tipo_audiencia = ANY (p.tipo_inicial || p.tipo_una || p.tipo_instrucao)
        AND tpt.cd_processo_status = 'D'
        AND date_trunc('day', tpa.dt_inicio) > '${VAR_ULT_DT_AUDIENCIA}'
        -- TODO(confirmar): buffer de segurança para a janela de 3 dias úteis fechar antes da
        -- audiência entrar no resultado. 10 dias corridos cobre folgadamente 3 dias úteis mesmo
        -- com fim de semana + 1 feriado no meio; ajustar depois que o cálculo real de dias
        -- úteis (CTE calendario_3du abaixo) estiver validado.
        and date_trunc('day', tpa.dt_fim) <= date_trunc('day', current_date - 10)
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

-- Data-limite do 3º dia útil após a audiência, calculada a partir de
-- pje.tb_calendario_eventos. Regra definida pelo usuário: dia útil = não suspende
-- audiência E não suspende prazo. Abrangência: nacional (id_orgao_julgador/id_estado
-- IS NULL) ou estado de SP (id_estado = 26).
-- TODO(confirmar): id_municipio não está sendo considerado (usuário só mencionou estado);
-- se houver feriado municipal relevante para alguma vara, precisa entrar aqui também.
calendario_3du AS (
    SELECT
        r.id_processo_audiencia,
        (
            SELECT dia::date
            FROM (
                SELECT dia, ROW_NUMBER() OVER (ORDER BY dia) AS rn
                FROM generate_series(
                    r.dta_audiencia::date + INTERVAL '1 day',
                    r.dta_audiencia::date + INTERVAL '15 day',
                    INTERVAL '1 day'
                ) AS dia
                WHERE EXTRACT(DOW FROM dia) NOT IN (0, 6)  -- exclui sáb/dom
                  AND NOT EXISTS (
                      SELECT 1
                      FROM pje.tb_calendario_eventos ce
                      WHERE ce.in_ativo = 'S'
                        AND (ce.in_suspende_prazo = 'S' OR ce.in_suspende_audiencia = 'S')
                        AND (ce.id_orgao_julgador IS NULL OR ce.id_orgao_julgador = r.id_orgao_julgador)
                        AND (ce.id_estado IS NULL OR ce.id_estado = 26) -- SP
                        AND make_date(ce.dt_ano, ce.dt_mes, ce.dt_dia) = dia::date
                  )
            ) dias_uteis
            WHERE dias_uteis.rn = 3
        ) AS limite_3_dias_uteis
    FROM audiencias_realizadas r
),

-- Movimentos de diligência (perícia ativa, ofício, carta precatória, mandado)
-- em até 3 dias úteis após a audiência.
-- TODO(confirmar): textos/códigos reais em ds_movimento (rodar query 4.2 do doc de análise)
-- e a condição de "laudo em aberto com prazo válido" da perícia ativa (tabela de
-- perito/laudo ainda não localizada — ver seção 3 do doc).
movimentos_diligencia AS (
    SELECT DISTINCT r.id_processo_audiencia
    FROM audiencias_realizadas r
    INNER JOIN calendario_3du cal ON cal.id_processo_audiencia = r.id_processo_audiencia
    INNER JOIN pje.tb_processo_evento tpe ON tpe.id_processo = r.num_proc_id_origem
    INNER JOIN pje.tb_evento e ON e.id_evento = tpe.id_evento
    INNER JOIN pje.tb_evento_processual ep ON ep.id_evento_processual = e.id_evento
    WHERE tpe.dt_atualizacao BETWEEN date_trunc('day', r.dta_audiencia::date)
        AND cal.limite_3_dias_uteis + INTERVAL '1 day' - INTERVAL '1 second'
        AND (
            ep.ds_movimento ILIKE '%perícia%'          -- TODO(confirmar): + condição de laudo em aberto/prazo válido
            OR ep.ds_movimento ILIKE '%expedição de ofício%'
            OR ep.ds_movimento ILIKE '%expedição de carta precatória%'
            OR ep.ds_movimento ILIKE '%expedição de mandado%'
        )
),

-- Movimentos de encerramento (conclusão/prolação de sentença, homologação de
-- acordo, marcação de julgamento) em até 3 dias úteis.
movimentos_julgamento AS (
    SELECT DISTINCT r.id_processo_audiencia
    FROM audiencias_realizadas r
    CROSS JOIN parametros p
    INNER JOIN calendario_3du cal ON cal.id_processo_audiencia = r.id_processo_audiencia
    LEFT JOIN pje.tb_processo_evento tpe ON tpe.id_processo = r.num_proc_id_origem
        AND tpe.dt_atualizacao BETWEEN date_trunc('day', r.dta_audiencia::date)
            AND cal.limite_3_dias_uteis + INTERVAL '1 day' - INTERVAL '1 second'
    LEFT JOIN pje.tb_evento e ON e.id_evento = tpe.id_evento
    LEFT JOIN pje.tb_evento_processual ep ON ep.id_evento_processual = e.id_evento
        AND (
            tpe.ds_texto_final_externo ILIKE 'Conclusos%sentença%'
            OR ep.ds_movimento ILIKE '%prolação%sentença%'
            OR ep.ds_movimento ILIKE '%homologação%acordo%'
        )
    LEFT JOIN proxima_audiencia pa ON pa.id_processo_audiencia = r.id_processo_audiencia
        AND pa.id_tipo_audiencia_proxima = ANY (p.tipo_julgamento)
        AND pa.dt_marcacao <= cal.limite_3_dias_uteis
    WHERE ep.id_evento_processual IS NOT NULL OR pa.id_processo_audiencia IS NOT NULL
),

classificacao AS (
    SELECT
        r.*,
        CASE
            -- 1) Regra geral: redesignação da mesma categoria (Inicial->Inicial,
            --    UNA->UNA, Instrução->Instrução — cobre variantes sumaríssimo/videoconf
            --    porque comparamos o id exato da próxima com o id exato da atual)
            WHEN pa.id_tipo_audiencia_proxima = r.id_tipo_audiencia_origem THEN 'Adiada'

            -- 2) Audiência Inicial: qualquer subsequente conta como efetiva
            WHEN r.id_tipo_audiencia = ANY (p.tipo_inicial)
                 AND pa.id_tipo_audiencia_proxima IS NOT NULL THEN 'Efetiva'

            -- 3) UNA -> Instrução (bipartição)
            WHEN r.id_tipo_audiencia = ANY (p.tipo_una)
                 AND pa.id_tipo_audiencia_proxima = ANY (p.tipo_instrucao)
                 AND md.id_processo_audiencia IS NOT NULL
                 -- TODO(confirmar): também exigir Encerramento de Instrução designado
                 THEN 'Efetiva'
            WHEN r.id_tipo_audiencia = ANY (p.tipo_una)
                 AND pa.id_tipo_audiencia_proxima = ANY (p.tipo_instrucao)
                 AND md.id_processo_audiencia IS NULL
                 AND mj.id_processo_audiencia IS NOT NULL THEN 'Efetiva'
            WHEN r.id_tipo_audiencia = ANY (p.tipo_una)
                 AND pa.id_tipo_audiencia_proxima = ANY (p.tipo_instrucao)
                 THEN 'Adiada' -- bipartição injustificada

            -- 4) Instrução
            WHEN r.id_tipo_audiencia = ANY (p.tipo_instrucao)
                 AND md.id_processo_audiencia IS NOT NULL
                 -- TODO(confirmar): exigir Encerramento de Instrução designado
                 THEN 'Efetiva'
            WHEN r.id_tipo_audiencia = ANY (p.tipo_instrucao)
                 AND md.id_processo_audiencia IS NULL
                 AND mj.id_processo_audiencia IS NOT NULL THEN 'Efetiva'

            ELSE 'Adiada'
        END AS status
    FROM audiencias_realizadas r
    CROSS JOIN parametros p
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
