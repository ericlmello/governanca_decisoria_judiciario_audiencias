/*
 * Audiências realizadas (Efetiva/Adiada) segundo os critérios do documento
 * "PAI - Critérios Audiências SETIC".
 *
 * Regras implementadas:
 *   0. Sinal legado (incompetência declarada/exceção de incompetência acolhida) -> EFETIVA,
 *      com prioridade sobre todas as outras regras. Herdado da query original (não está no
 *      documento de critérios).
 *   1. Regra geral: redesignação de audiência da MESMA categoria (agrupando variantes
 *      sumaríssimo/videoconferência) -> ADIADA.
 *   2. Inicial: qualquer audiência subsequente (UNA/Instrução/Encerramento de
 *      Instrução/Julgamento/Conciliação) OU prolação de sentença/acordo direto (sem nova
 *      audiência) -> EFETIVA.
 *   3. UNA: bipartição (Instrução OU Encerramento de Instrução designado) -> ADIADA por padrão,
 *      exceto:
 *        a) diligência E Encerramento de Instrução designado (ambos, não só a diligência) em
 *           até 3 dias úteis -> EFETIVA
 *        b) sem diligência + Julgamento OU Conciliação (ou conclusão/prolação de sentença/
 *           homologação de acordo) em até 3 dias úteis -> EFETIVA
 *        c) nenhum movimento -> ADIADA (bipartição injustificada)
 *        d) UNA seguida de qualquer outro tipo avaliado (ex.: Julgamento ou Conciliação direto,
 *           fora da janela de 3 dias úteis) -> EFETIVA, por analogia com a regra da Inicial
 *   4. Instrução: diligência E Encerramento de Instrução -> EFETIVA;
 *      diligência E Julgamento OU Conciliação (mesmo sem Encerramento formal) -> EFETIVA;
 *      sem diligência + Julgamento OU Conciliação -> EFETIVA;
 *      sem diligência + Encerramento de Instrução designado -> ADIADA;
 *      seguida de qualquer outro tipo avaliado (ex.: fora da janela de 3 dias úteis) -> EFETIVA,
 *      por analogia com a regra da Inicial e da UNA (regra 7);
 *      sem nenhum sinal subsequente e sem nenhuma próxima audiência -> ADIADA.
 *   5. Perícia ativa (laudo em aberto, prazo válido) conta como diligência se MARCADA dentro da
 *      janela de 3 dias úteis, independente de status ou prazo posterior. Perícia com prazo
 *      vencido não é tratada aqui (regra pertence ao painel de perícias do PAI, fora de escopo).
 *   6. Tipo 8 "Instrução e Julgamento": regra própria, sempre EFETIVA (exceto redesignação de
 *      mesma categoria, regra 1) - julgamento ocorre no mesmo ato, não depende de sinal
 *      posterior como a Instrução comum.
 *   7. UNA ou Instrução seguida de tipo que não é a mesma categoria nem a bipartição esperada
 *      (ex.: Julgamento ou Conciliação direto) -> EFETIVA, por analogia com a regra da Inicial.
 *
 * Mapeamento de pje.tb_tipo_audiencia (36 tipos cadastrados):
 *   Inicial ..................... 3, 16 (sumaríssimo), 22 (videoconf), 29 (videoconf sumaríssimo)
 *   UNA .......................... 5, 19 (sumaríssimo), 23 (videoconf), 31 (videoconf sumaríssimo),
 *                                  7 e 9 (Rito Sumário)
 *   Instrução .................... 6, 12 (sumaríssimo), 24 (videoconf), 27 (videoconf sumaríssimo)
 *   Encerramento de Instrução .... 10, 25 (videoconf)
 *   Julgamento ................... 4
 *   Conciliação em Conhecimento .. 1, 32, 20, 33 (usada como SINAL, ver regras 2/3b/4b - não faz
 *                                  parte da população avaliada; Conciliação em Execução não conta)
 *   Instrução e Julgamento ....... 8 (regra própria, ver regra 6)
 *
 * Tipos totalmente fora da população avaliada: Conciliação em Conhecimento e em Execução (usadas
 * só como sinal, ver acima), Inquirição de testemunha - juízo deprecado (11, 26), Justificação
 * Prévia (18), Mediação (13, 14, 15, 28), Pública (17, 30).
 *
 * Códigos de movimento (pje.tb_evento_processual / tpe.id_evento):
 *   Conclusão para sentença ...... 51 (+ ds_texto_final_externo ILIKE '%sentença%')
 *   Prolação de sentença COM resolução de mérito .. 385, 219, 220, 221, 442, 444, 446, 448, 450,
 *                                  452, 455, 466, 471, 11795, 50103
 *   Prolação de sentença SEM resolução de mérito / terminativa .. 218, 454, 457, 458, 459, 460,
 *                                  461, 462, 463, 464, 465, 472, 473
 *   Homologação de acordo ........ 466 (Homologada a transação - já incluído na lista acima, não
 *                                  repetido separadamente)
 *   Expedição ofício/carta precatória/mandado .. não é movimento em tb_processo_evento; vem de
 *                                  tb_processo_expediente.id_tipo_processo_documento, join com
 *                                  tb_tipo_processo_documento.ds_tipo_processo_documento ILIKE
 *                                  ANY ('Ofício%', 'Carta Precatória%', 'Mandado%') - filtro por
 *                                  prefixo no catálogo estruturado, não no texto livre do evento.
 *   Perícia ativa ................ não é movimento em tb_processo_evento; vem de
 *                                  tb_processo_pericia (painel de perícias do PAI) - status
 *                                  aberto (L/S/A/M) + prazo válido
 *                                  (tb_proc_parte_expediente.dt_prazo_legal_parte >=
 *                                  CURRENT_DATE - 1 dia), via tb_processo_expediente com
 *                                  ds_origem_expediente = 'PERICIA'.
 *
 * Sinal legado de incompetência: ids 941 (Declarada a incompetência) e 371 (Acolhida a exceção
 * de incompetência) - herdado da query original, com prioridade máxima no CASE de
 * classificacao, para todos os tipos avaliados (Inicial/UNA/Instrução).
 *
 * Janela de 3 dias úteis: aplica-se apenas onde indicado (regras 3 e 4, UNA/Instrução). A Regra
 * Geral (1) e a regra da Inicial (2) não têm janela.
 *
 * Abrangência do calendário de dias úteis (pje.tb_calendario_eventos): nacional
 * (id_orgao_julgador/id_estado/id_municipio IS NULL), estado de SP (id_estado = 26), ou
 * município específico da vara (id_municipio = id_municipio_vara) - granular, vale só para as
 * varas daquele município. Município da vara obtido via tb_orgao_julgador.id_localizacao ->
 * tb_localizacao.id_endereco -> tb_endereco.id_cep -> tb_cep.id_municipio.
 *
 * Watermark de carga (VAR_ULT_DT_AUDIENCIA): lido da própria tabela de destino
 * (SELECT MAX(dt_audiencia) FROM pai_2_0.audiencias WHERE status <> 'Programada') -
 * autorreferente por design.
 */

WITH parametros AS (
    SELECT
        ARRAY[3, 16, 22, 29]       AS tipo_inicial,
        ARRAY[5, 19, 23, 31, 7, 9] AS tipo_una, -- 7/9 = Rito Sumário
        ARRAY[6, 12, 24, 27]       AS tipo_instrucao,
        ARRAY[10, 25]              AS tipo_encerramento_instrucao,
        ARRAY[4]                   AS tipo_julgamento,
        ARRAY[8]                   AS tipo_instrucao_julgamento, -- "Instrução e Julgamento":
            -- julgamento no mesmo ato; regra própria (ver classificacao), não segue a árvore
            -- normal da Instrução
        ARRAY[1, 32, 20, 33]       AS tipo_conciliacao -- Conciliação em Conhecimento; usada como
            -- sinal explícito de Efetiva (Inicial/UNA/Instrução). Conciliação em Execução não conta.
),

audiencias_realizadas AS (
    SELECT tp.id_processo,
        tpa.id_processo_trf AS num_proc_id_origem,
        tpa.id_processo_audiencia,
        tpa.dt_inicio dta_audiencia,
        tp.nr_processo,
        toj.id_orgao_julgador,
        tcep.id_municipio AS id_municipio_vara, -- município da vara, via
            -- tb_orgao_julgador.id_localizacao -> tb_localizacao.id_endereco ->
            -- tb_endereco.id_cep -> tb_cep.id_municipio
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
    LEFT JOIN
        pje.tb_localizacao tloc ON tloc.id_localizacao = toj.id_localizacao
    LEFT JOIN
        pje.tb_endereco tend ON tend.id_endereco = tloc.id_endereco
    LEFT JOIN
        pje.tb_cep tcep ON tcep.id_cep = tend.id_cep
    INNER JOIN
        pje.tb_usuario_login tul ON tul.id_usuario = tpa.id_pessoa_realizador
    inner join tb_classe_judicial c
        on c.id_classe_judicial = tpt.id_classe_judicial
    inner join tb_agrupamento_fase fase
        on fase.id_agrupamento_fase = tp.id_agrupamento_fase
        and fase.in_ativo = 'S'
    WHERE
        tpa.cd_status_audiencia = 'F'
        -- População avaliada = os tipos com regra definida no documento (Inicial/UNA/
        -- Instrução) + tipo 8 "Instrução e Julgamento" (regra própria, ver classificacao).
        -- Encerramento de Instrução e Julgamento são "sinais", não audiências cuja
        -- efetividade é medida.
        AND tpa.id_tipo_audiencia = ANY (p.tipo_inicial || p.tipo_una || p.tipo_instrucao || p.tipo_instrucao_julgamento)
        AND tpt.cd_processo_status = 'D'
        AND date_trunc('day', tpa.dt_inicio) > '${VAR_ULT_DT_AUDIENCIA}'
        -- VAR_ULT_DT_AUDIENCIA vem da própria tabela de destino (marca d'água/watermark):
        --   SELECT MAX(dt_audiencia) AS ultima_dt
        --   FROM pai_2_0.audiencias
        --   WHERE status <> 'Programada'
        -- Ou seja, é AUTORREFERENTE: a query lê da mesma tabela em que grava. Como o limite de
        -- 3 dias úteis varia por vara (calendário local), duas audiências do mesmo dia podem
        -- fechar a janela em datas diferentes; uma vez que qualquer audiência daquele dia (ou
        -- posterior) é gravada, `dt_inicio > ultima_dt` exclui permanentemente as demais do
        -- mesmo dia ainda não processadas, mesmo que a janela delas feche depois - sem retry
        -- automático. Comportamento mantido intencionalmente.
        --
        -- Pré-filtro barato: 3 dias úteis exigem no mínimo 3 dias corridos. O corte real (janela
        -- já fechada) é feito no SELECT final, sobre calendario_3du.limite_3_dias_uteis.
        and date_trunc('day', tpa.dt_fim) <= date_trunc('day', current_date - 4)
),

-- TODAS as audiências subsequentes (não só a próxima) designadas para o mesmo processo após a
-- atual. Necessária porque, na bipartição UNA->Instrução, o "Encerramento de Instrução" e o
-- "Julgamento" normalmente NÃO são a audiência imediatamente seguinte (esse lugar já é ocupado
-- pela Instrução) - são audiências posteriores a ela.
audiencias_subsequentes AS (
    SELECT
        r.id_processo_audiencia,
        tpa2.id_tipo_audiencia,
        tpa2.dt_marcacao,
        ROW_NUMBER() OVER (PARTITION BY r.id_processo_audiencia ORDER BY tpa2.dt_marcacao ASC) AS ordem
    FROM audiencias_realizadas r
    INNER JOIN pje.tb_processo_audiencia tpa2
        ON tpa2.id_processo_trf = r.num_proc_id_origem
        AND tpa2.dt_marcacao > r.dta_audiencia
),

-- Próxima audiência (a imediatamente seguinte, ordem = 1) - usada só para as checagens que de
-- fato dependem de "qual é a próxima": regra geral de mesma categoria, Inicial->qualquer
-- subsequente, e UNA->Instrução/Encerramento define bipartição.
proxima_audiencia AS (
    SELECT
        id_processo_audiencia,
        id_tipo_audiencia AS id_tipo_audiencia_proxima,
        dt_marcacao
    FROM audiencias_subsequentes
    WHERE ordem = 1
),

-- Sinal de prolação de sentença/acordo homologado SEM nova audiência designada - trigger
-- adicional da regra da Inicial ("... ou ocorre a prolação da sentença"). SEM janela de 3 dias
-- úteis, igual às demais checagens da Regra 1/2 (só UNA/Instrução têm janela) - por isso não
-- reaproveita movimentos_julgamento (que É limitada pela janela de calendario_3du), e sim
-- reimplementa a mesma lista de códigos sem o filtro de data superior.
sentenca_ou_acordo_sem_janela AS (
    SELECT DISTINCT r.id_processo_audiencia
    FROM audiencias_realizadas r
    INNER JOIN pje.tb_processo_evento tpe ON tpe.id_processo = r.num_proc_id_origem
    WHERE tpe.dt_atualizacao > r.dta_audiencia
        AND (
            (tpe.id_evento = 51 AND tpe.ds_texto_final_externo ILIKE '%sentença%') -- Conclusão p/ sentença
            OR tpe.id_evento IN (
                -- Prolação de sentença COM resolução de mérito
                385, 219, 220, 221, 442, 444, 446, 448, 450, 452, 455, 466, 471, 11795, 50103,
                -- Prolação de sentença SEM resolução de mérito / terminativa
                218, 454, 457, 458, 459, 460, 461, 462, 463, 464, 465, 472, 473
            )
        )
),

-- Data-limite do 3º dia útil após a audiência, calculada a partir de pje.tb_calendario_eventos.
-- Dia útil = não suspende audiência E não suspende prazo. Abrangência: nacional
-- (id_orgao_julgador/id_estado/id_municipio IS NULL), estado de SP (id_estado = 26), ou
-- município específico da vara (id_municipio = id_municipio_vara) - granular.
-- Eventos com período (dt_*_final preenchido, ex.: recesso forense 20/12 a 20/01) bloqueiam o
-- intervalo inteiro, não só o dia inicial. Busca até 60 dias à frente para atravessar o recesso.
-- in_ativo e in_suspende_prazo são do domínio pje."boleano" (tipo base não confirmado): o ::text
-- funciona tanto se for boolean ('true') quanto char ('S').
-- Feriados fixos recorrentes (dt_ano IS NULL, ex.: aniversário do município) repetem todo ano -
-- a data é remontada com o ANO do dia sendo testado, em vez de usar make_date(NULL, ...), que
-- retornaria NULL e faria o BETWEEN falhar silenciosamente (728 registros confirmados com
-- dt_ano IS NULL em 2026-10-02).
calendario_3du AS (
    SELECT
        r.id_processo_audiencia,
        (
            SELECT dia::date
            FROM (
                SELECT dia, ROW_NUMBER() OVER (ORDER BY dia) AS rn
                FROM generate_series(
                    r.dta_audiencia::date + INTERVAL '1 day',
                    r.dta_audiencia::date + INTERVAL '60 day',
                    INTERVAL '1 day'
                ) AS dia
                WHERE EXTRACT(DOW FROM dia) NOT IN (0, 6)  -- exclui sáb/dom
                  AND NOT EXISTS (
                      SELECT 1
                      FROM pje.tb_calendario_eventos ce
                      WHERE ce.in_ativo::text IN ('S', 'true')
                        AND (ce.in_suspende_prazo::text IN ('S', 'true') OR ce.in_suspende_audiencia = 'S')
                        AND (ce.id_orgao_julgador IS NULL OR ce.id_orgao_julgador = r.id_orgao_julgador)
                        AND (ce.id_estado IS NULL OR ce.id_estado = 26) -- SP
                        AND (ce.id_municipio IS NULL OR ce.id_municipio = r.id_municipio_vara)
                        AND (
                            (ce.dt_ano IS NOT NULL
                             AND dia::date BETWEEN make_date(ce.dt_ano, ce.dt_mes, ce.dt_dia)
                                 AND make_date(COALESCE(ce.dt_ano_final, ce.dt_ano),
                                               COALESCE(ce.dt_mes_final, ce.dt_mes),
                                               COALESCE(ce.dt_dia_final, ce.dt_dia))
                            )
                            OR
                            (ce.dt_ano IS NULL
                             AND dia::date BETWEEN make_date(EXTRACT(YEAR FROM dia)::int, ce.dt_mes, ce.dt_dia)
                                 AND make_date(EXTRACT(YEAR FROM dia)::int,
                                               COALESCE(ce.dt_mes_final, ce.dt_mes),
                                               COALESCE(ce.dt_dia_final, ce.dt_dia))
                            )
                        )
                  )
            ) dias_uteis
            WHERE dias_uteis.rn = 3
        ) AS limite_3_dias_uteis
    FROM audiencias_realizadas r
),

-- Movimentos de diligência (perícia ativa, ofício, carta precatória, mandado) em até 3 dias
-- úteis após a audiência.
-- Expedição de ofício/carta precatória/mandado: vem de tb_processo_expediente
-- (id_processo_trf, dt_criacao_expediente, id_tipo_processo_documento), que já é usada aqui
-- mesmo para perícia (join via tb_proc_parte_expediente). O campo id_tipo_processo_documento
-- referencia tb_tipo_processo_documento (id_tipo_processo_documento, ds_tipo_processo_documento,
-- in_ativo), que tem os tipos ofício/carta precatória/mandado - inclusive vários subtipos
-- específicos e ativos (ex.: "Mandado de Citação", "Carta Precatória Executória", "Ofício
-- Precatório"), então o filtro usa ILIKE por PREFIXO no nome canônico (não no texto livre do
-- evento), o que é robusto porque o vocabulário é controlado (catálogo), não texto digitado.
-- ds_origem_expediente NÃO diferencia por tipo de documento (valores confirmados: LEGADO,
-- INTIMACAO_AUTOMATICA, NOTIFICACAO_EXPRESSA, PEC_FLUXO, PEC_MENU, PERICIA) - é outra dimensão
-- (canal/origem de geração do expediente), por isso a diferenciação usa
-- tb_tipo_processo_documento, não esse campo.
--
-- Perícia ativa: query do "painel de perícias do PAI" (mesma consulta usada tanto para prazo
-- válido quanto vencido - a diferença está em como o prazo é interpretado depois). Aqui só
-- entra a perícia ATIVA (laudo em aberto) com PRAZO VÁLIDO; prazo vencido segue as regras do
-- painel de perícias do PAI (fora de escopo, ver regra 5 do cabeçalho).
-- Perícia MARCADA dentro da janela de 3 dias úteis (pp.dt_marcacao) conta como diligência,
-- independente de status ou prazo posterior.
-- Referência de "prazo válido" = CURRENT_DATE - 1 dia, igual à "Data de referência do relatório"
-- do painel de perícias original.
movimentos_diligencia AS (
    SELECT DISTINCT r.id_processo_audiencia
    FROM audiencias_realizadas r
    INNER JOIN calendario_3du cal ON cal.id_processo_audiencia = r.id_processo_audiencia
    INNER JOIN pje.tb_processo_expediente pex ON pex.id_processo_trf = r.num_proc_id_origem
    INNER JOIN pje.tb_tipo_processo_documento tpd
        ON tpd.id_tipo_processo_documento = pex.id_tipo_processo_documento
    WHERE pex.dt_criacao_expediente BETWEEN date_trunc('day', r.dta_audiencia::date)
        AND cal.limite_3_dias_uteis + INTERVAL '1 day' - INTERVAL '1 second'
        AND tpd.ds_tipo_processo_documento ILIKE ANY (ARRAY[
            'Ofício%', 'Carta Precatória%', 'Mandado%'
        ])

    UNION

    SELECT DISTINCT r.id_processo_audiencia
    FROM audiencias_realizadas r
    INNER JOIN calendario_3du cal ON cal.id_processo_audiencia = r.id_processo_audiencia
    INNER JOIN pje.tb_processo_pericia pp ON pp.id_processo_trf = r.num_proc_id_origem
    INNER JOIN pje.tb_proc_parte_expediente ppex
        ON ppex.id_processo_parte_expediente = pp.id_proc_parte_exp_ultimo
    INNER JOIN pje.tb_processo_expediente pex ON pex.id_processo_expediente = ppex.id_processo_expediente
    LEFT JOIN pje.tb_pess_doc_identificacao pdi ON pdi.id_pessoa = pp.id_pessoa_perito
    WHERE pp.cd_status_pericia IN ('L', 'S', 'A', 'M') -- laudo em aberto (não finalizado)
        AND pex.ds_origem_expediente = 'PERICIA'
        AND pdi.in_principal = 'S'
        AND ppex.dt_prazo_legal_parte >= CURRENT_DATE - INTERVAL '1 day' -- prazo válido/não vencido
        AND pp.dt_marcacao BETWEEN date_trunc('day', r.dta_audiencia::date)
            AND cal.limite_3_dias_uteis + INTERVAL '1 day' - INTERVAL '1 second'
),

-- Sinal legado da query original: Declarada a incompetência (941) / Acolhida a exceção de
-- incompetência (371) dentro da janela também torna a audiência Efetiva, com prioridade máxima
-- no CASE de classificacao, para todos os tipos (Inicial/UNA/Instrução). A janela usada é a de
-- 3 dias úteis do restante da v2 (calendario_3du).
incompetencia_na_janela AS (
    SELECT DISTINCT r.id_processo_audiencia
    FROM audiencias_realizadas r
    INNER JOIN calendario_3du cal ON cal.id_processo_audiencia = r.id_processo_audiencia
    INNER JOIN pje.tb_processo_evento tpe ON tpe.id_processo = r.num_proc_id_origem
    WHERE tpe.dt_atualizacao BETWEEN date_trunc('day', r.dta_audiencia::date)
        AND cal.limite_3_dias_uteis + INTERVAL '1 day' - INTERVAL '1 second'
        AND tpe.id_evento IN (941, 371) -- Declarada a incompetência / Acolhida exceção de incompetência
),

-- Encerramento de Instrução designado dentro da janela de 3 dias úteis - checagem GERAL
-- (qualquer audiência subsequente desse tipo dentro da janela, via audiencias_subsequentes),
-- não só "a próxima". Na bipartição UNA->Instrução, o Encerramento normalmente vem DEPOIS da
-- Instrução (que já ocupa o lugar de "próxima"). A designação de Encerramento de Instrução é
-- exigida JUNTO com a diligência para o resultado Efetiva - não basta a diligência sozinha.
encerramento_instrucao_na_janela AS (
    SELECT DISTINCT s.id_processo_audiencia
    FROM audiencias_subsequentes s
    CROSS JOIN parametros p
    INNER JOIN calendario_3du cal ON cal.id_processo_audiencia = s.id_processo_audiencia
    WHERE s.id_tipo_audiencia = ANY (p.tipo_encerramento_instrucao)
      AND s.dt_marcacao <= cal.limite_3_dias_uteis
),

-- Movimentos de encerramento (conclusão/prolação de sentença, homologação de acordo, marcação
-- de Julgamento ou Conciliação) em até 3 dias úteis.
--   - Conclusão para sentença: código 51 "Conclusos os autos para #{tipo de conclusão}...".
--   - Prolação de sentença: cobre tanto sentença COM resolução de mérito (guarda-chuva 385:
--     219/220/221/442/444/446/448/450/452/455/466/471/11795/50103) quanto SEM resolução de
--     mérito/terminativa (guarda-chuva 218: 454/457/458/459/460/461/462/463/464/465/472/473).
--     Ambas contam como "Prolação de sentença".
--   - Homologação de acordo: termo técnico trabalhista é "transação" - código 466 "Homologada
--     a transação" (já incluído na lista de mérito acima, não repetido separadamente).
--   - Marcação de audiência de Julgamento OU Conciliação: QUALQUER audiência subsequente desses
--     tipos dentro da janela (via audiencias_subsequentes), mesmo raciocínio do Encerramento de
--     Instrução acima. Conciliação é aceita como sinal equivalente ao Julgamento.
movimentos_julgamento AS (
    SELECT DISTINCT r.id_processo_audiencia
    FROM audiencias_realizadas r
    INNER JOIN calendario_3du cal ON cal.id_processo_audiencia = r.id_processo_audiencia
    INNER JOIN pje.tb_processo_evento tpe ON tpe.id_processo = r.num_proc_id_origem
    WHERE tpe.dt_atualizacao BETWEEN date_trunc('day', r.dta_audiencia::date)
        AND cal.limite_3_dias_uteis + INTERVAL '1 day' - INTERVAL '1 second'
        AND (
            (tpe.id_evento = 51 AND tpe.ds_texto_final_externo ILIKE '%sentença%') -- Conclusão p/ sentença
            OR tpe.id_evento IN (
                -- Prolação de sentença COM resolução de mérito
                385, 219, 220, 221, 442, 444, 446, 448, 450, 452, 455, 466, 471, 11795, 50103,
                -- Prolação de sentença SEM resolução de mérito / terminativa
                218, 454, 457, 458, 459, 460, 461, 462, 463, 464, 465, 472, 473
            )
        )

    UNION

    SELECT DISTINCT s.id_processo_audiencia
    FROM audiencias_subsequentes s
    CROSS JOIN parametros p
    INNER JOIN calendario_3du cal ON cal.id_processo_audiencia = s.id_processo_audiencia
    WHERE s.id_tipo_audiencia = ANY (p.tipo_julgamento || p.tipo_conciliacao)
      AND s.dt_marcacao <= cal.limite_3_dias_uteis
),

classificacao AS (
    SELECT
        r.*,
        CASE
            -- 0) Sinal legado (incompetência) - prioridade máxima, igual à query original.
            --    Vale para todos os tipos avaliados.
            WHEN inc.id_processo_audiencia IS NOT NULL THEN 'Efetiva'

            -- 1) Regra geral: redesignação da MESMA CATEGORIA. Agrupa variantes sumaríssimo/
            --    videoconferência via os arrays de parametros. Inclui tipo_instrucao_julgamento
            --    (tipo 8): redesignado como novo tipo 8 sinaliza que o julgamento NÃO ocorreu no
            --    ato original, então a regra geral prevalece sobre a regra própria do tipo 8
            --    (item 1.5 abaixo) - por isso vem primeiro no CASE.
            WHEN (r.id_tipo_audiencia = ANY (p.tipo_inicial) AND pa.id_tipo_audiencia_proxima = ANY (p.tipo_inicial))
              OR (r.id_tipo_audiencia = ANY (p.tipo_una) AND pa.id_tipo_audiencia_proxima = ANY (p.tipo_una))
              OR (r.id_tipo_audiencia = ANY (p.tipo_instrucao) AND pa.id_tipo_audiencia_proxima = ANY (p.tipo_instrucao))
              OR (r.id_tipo_audiencia = ANY (p.tipo_instrucao_julgamento) AND pa.id_tipo_audiencia_proxima = ANY (p.tipo_instrucao_julgamento))
                THEN 'Adiada'

            -- 1.5) Tipo 8 "Instrução e Julgamento" - julgamento ocorre no mesmo ato, não depende
            --      de sinal posterior (diferente da Instrução comum, que precisa de um sinal
            --      futuro para provar que "funcionou"). Sempre Efetiva, exceto redesignação de
            --      mesma categoria (já tratada na regra 1 acima, com prioridade por vir antes).
            WHEN r.id_tipo_audiencia = ANY (p.tipo_instrucao_julgamento) THEN 'Efetiva'

            -- 2) Audiência Inicial: qualquer subsequente conta como efetiva. Inicial que termina
            --    direto em sentença/acordo homologado, SEM nova audiência, também é Efetiva.
            WHEN r.id_tipo_audiencia = ANY (p.tipo_inicial)
                 AND (pa.id_tipo_audiencia_proxima IS NOT NULL
                      OR sa.id_processo_audiencia IS NOT NULL) THEN 'Efetiva'

            -- 3) UNA -> Instrução OU Encerramento de Instrução (bipartição). A avaliação de
            --    diligência se aplica tanto quando a próxima audiência é Instrução quanto quando
            --    é Encerramento de Instrução DIRETO (pulando a Instrução). "Efetiva" por
            --    diligência exige TAMBÉM Encerramento de Instrução designado - não basta a
            --    diligência sozinha.
            WHEN r.id_tipo_audiencia = ANY (p.tipo_una)
                 AND pa.id_tipo_audiencia_proxima = ANY (p.tipo_instrucao || p.tipo_encerramento_instrucao)
                 AND md.id_processo_audiencia IS NOT NULL
                 AND enc.id_processo_audiencia IS NOT NULL
                THEN 'Efetiva'
            -- 3b) sem diligência + Julgamento OU Conciliação designado (ou conclusão/prolação de
            --     sentença/homologação de acordo) -> Efetiva.
            WHEN r.id_tipo_audiencia = ANY (p.tipo_una)
                 AND pa.id_tipo_audiencia_proxima = ANY (p.tipo_instrucao || p.tipo_encerramento_instrucao)
                 AND md.id_processo_audiencia IS NULL
                 AND mj.id_processo_audiencia IS NOT NULL THEN 'Efetiva'
            -- 3c) nenhum movimento + designa Instrução OU Encerramento de Instrução -> Adiada
            --     (bipartição injustificada). Cobre inclusive diligência SEM Encerramento de
            --     Instrução designado, que cai aqui por eliminação das duas condições acima.
            WHEN r.id_tipo_audiencia = ANY (p.tipo_una)
                 AND pa.id_tipo_audiencia_proxima = ANY (p.tipo_instrucao || p.tipo_encerramento_instrucao)
                 THEN 'Adiada'

            -- 3d) UNA seguida de qualquer OUTRO tipo avaliado que não seja mesma categoria
            --     (regra 1) nem Instrução/Encerramento de Instrução (bipartição, regras 3a-3c) -
            --     na prática, Julgamento ou Conciliação designados diretamente fora da janela de
            --     3 dias úteis (dentro da janela já são capturados por mj/regra 3b). Conta como
            --     Efetiva, por analogia com a regra da Inicial.
            WHEN r.id_tipo_audiencia = ANY (p.tipo_una)
                 AND pa.id_tipo_audiencia_proxima IS NOT NULL THEN 'Efetiva'

            -- 4) Instrução - mesma lógica de exigir Encerramento de Instrução junto com a
            --    diligência aplicada à UNA.
            WHEN r.id_tipo_audiencia = ANY (p.tipo_instrucao)
                 AND md.id_processo_audiencia IS NOT NULL
                 AND enc.id_processo_audiencia IS NOT NULL
                THEN 'Efetiva'
            -- 4a) diligência E Julgamento/Conciliação designado, mesmo SEM Encerramento de
            --     Instrução formal - diligência cumprida e processo já avançou para julgamento.
            WHEN r.id_tipo_audiencia = ANY (p.tipo_instrucao)
                 AND md.id_processo_audiencia IS NOT NULL
                 AND mj.id_processo_audiencia IS NOT NULL
                THEN 'Efetiva'
            -- 4b) sem diligência + Julgamento OU Conciliação designado -> Efetiva.
            WHEN r.id_tipo_audiencia = ANY (p.tipo_instrucao)
                 AND md.id_processo_audiencia IS NULL
                 AND mj.id_processo_audiencia IS NOT NULL THEN 'Efetiva'

            -- 4c) Sem diligências + Encerramento de Instrução designado -> Adiada. Redesignar
            --     Encerramento de Instrução sem nenhum sinal de diligência é tratado como
            --     bipartição injustificada, mesma lógica da UNA (regra 3c).
            WHEN r.id_tipo_audiencia = ANY (p.tipo_instrucao)
                 AND md.id_processo_audiencia IS NULL
                 AND enc.id_processo_audiencia IS NOT NULL
                THEN 'Adiada'

            -- 4d) Instrução seguida de qualquer OUTRA audiência marcada (mesmo fora da janela de
            --     3 dias úteis, sem nenhum outro sinal dentro dela) - Efetiva, por analogia com a
            --     regra 3d da UNA.
            WHEN r.id_tipo_audiencia = ANY (p.tipo_instrucao)
                 AND pa.id_tipo_audiencia_proxima IS NOT NULL THEN 'Efetiva'

            -- Instrução sem diligência, sem Julgamento/Conciliação designado, sem Encerramento
            -- de Instrução designado e sem nenhuma próxima audiência - nenhum sinal registrado.
            -- Cai aqui por omissão (Adiada).
            ELSE 'Adiada'
        END AS status
    FROM audiencias_realizadas r
    CROSS JOIN parametros p
    LEFT JOIN proxima_audiencia pa ON pa.id_processo_audiencia = r.id_processo_audiencia
    LEFT JOIN movimentos_diligencia md ON md.id_processo_audiencia = r.id_processo_audiencia
    LEFT JOIN movimentos_julgamento mj ON mj.id_processo_audiencia = r.id_processo_audiencia
    LEFT JOIN encerramento_instrucao_na_janela enc ON enc.id_processo_audiencia = r.id_processo_audiencia
    LEFT JOIN incompetencia_na_janela inc ON inc.id_processo_audiencia = r.id_processo_audiencia
    LEFT JOIN sentenca_ou_acordo_sem_janela sa ON sa.id_processo_audiencia = r.id_processo_audiencia
)
SELECT
    c.nr_processo, c.id_processo,
    c.id_orgao_julgador,
    c.dta_audiencia dt_audiencia,
    replace(c.ds_tipo_audiencia, ' por videoconferência', '') tipo_audiencia,
    case
        when STRPOS(c.ds_tipo_audiencia, ' por videoconferência') > 0 then
            'Videoconferência'
        else
            'Presencial'
    end modalidade,
    c.ds_classe_judicial,
    c.magistrado,
    c.status,
    c.fase,
    NULL::date AS dt_ult_mov,
    TO_CHAR(CURRENT_DATE, 'YYYY-MM-DD') AS dta_ref
FROM classificacao c
INNER JOIN calendario_3du cal ON cal.id_processo_audiencia = c.id_processo_audiencia
-- Só classifica quando a janela de 3 dias úteis já fechou. limite NULL (mais de 60 dias sem dia
-- útil) também fica de fora, em vez de virar "Adiada" por falta de sinais.
WHERE cal.limite_3_dias_uteis < CURRENT_DATE;
