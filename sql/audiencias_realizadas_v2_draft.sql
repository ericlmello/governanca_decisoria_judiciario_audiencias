/*
 * RASCUNHO — Audiências realizadas (Efetiva/Adiada) segundo os novos critérios
 * do documento "PAI - Critérios Audiências SETIC".
 *
 * NÃO EXECUTAR EM PRODUÇÃO ainda: pontos marcados com `-- TODO(confirmar)` ou
 * `-- TODO(decisão)` seguem pendentes. Ver docs/analise_criterios_audiencias_setic.md
 * para o comparativo completo com a query original (sql/audiencias_realizadas_original.sql).
 *
 * Regras implementadas (ver seção 2 do doc de análise):
 *   1. Regra geral: redesignação de audiência da MESMA categoria (agrupando variantes
 *      sumaríssimo/videoconferência) -> ADIADA.
 *   2. Inicial: qualquer audiência subsequente (UNA/Instrução/Encerramento de
 *      Instrução/Julgamento) -> EFETIVA.
 *   3. UNA: bipartição (Instrução designada) -> ADIADA por padrão, exceto:
 *        a) diligência E Encerramento de Instrução designado (AMBOS, não só a diligência)
 *           em até 3 dias úteis -> EFETIVA
 *        b) sem diligência + Julgamento (ou conclusão/prolação sentença/
 *           homologação de acordo) em até 3 dias úteis -> EFETIVA
 *   4. Instrução: diligência E Encerramento de Instrução -> EFETIVA;
 *      sem diligência + Julgamento -> EFETIVA.
 *   5. Perícia ativa (laudo em aberto, prazo válido) -> conta como diligência. Perícia com
 *      prazo VENCIDO não é tratada aqui (regra pertence ao painel de perícias do PAI —
 *      dependência externa, fora de escopo).
 *
 * CORREÇÕES feitas numa releitura cuidadosa do documento (bugs de implementação da versão
 * anterior deste rascunho, não dúvidas de negócio — o texto do documento já respondia):
 *   a) Regra 1 comparava id_tipo_audiencia EXATO da próxima audiência com o da atual, então
 *      UNA presencial -> UNA videoconferência (ids diferentes, mesma categoria) não era detectado
 *      como "mesma categoria redesignada". Corrigido para comparar por grupo (array).
 *   b) Regras 3a e 4 checavam só a diligência, sem checar se Encerramento de Instrução também
 *      foi designado — mas o documento diz explicitamente "a designação de Encerramento de
 *      Instrução é obrigatória quando há diligências pendentes", ou seja, os dois sinais juntos
 *      são exigidos. Corrigido via nova CTE encerramento_instrucao_na_janela.
 *   c) "Marcação de audiência de julgamento" (regras 3b/4) só olhava a audiência imediatamente
 *      seguinte (proxima_audiencia, LIMIT 1) — mas na bipartição UNA->Instrução, o Julgamento
 *      normalmente vem DEPOIS da Instrução, não é "a próxima" em relação à UNA original. Corrigido
 *      com a nova CTE audiencias_subsequentes (todas as audiências futuras, não só a 1ª).
 *
 * LACUNAS NO PRÓPRIO DOCUMENTO (não são bug do rascunho — o texto simplesmente não cobre estes
 * casos; caem no ELSE 'Adiada' por omissão, mas merecem confirmação da SETIC):
 *   d) O que acontece se uma UNA é seguida de um tipo que NÃO é UNA nem Instrução (ex.:
 *      Encerramento de Instrução ou Julgamento designados diretamente, pulando a Instrução)?
 *      O documento só cobre "designa nova UNA" e "designa Instrução (bipartição)".
 *   e) Para Instrução (seção 2.4), qual o status quando NEM "diligência + Encerramento de
 *      Instrução" NEM "sem diligência + Julgamento" se aplicam (ex.: nada acontece depois)?
 *      Ao contrário da UNA (que tem o rótulo explícito "bipartição injustificada" para esse caso),
 *      o documento não dá um rótulo equivalente para a Instrução.
 *
 * Mapeamento de pje.tb_tipo_audiencia confirmado pelo usuário (36 tipos cadastrados):
 *   Inicial ..................... 3, 16 (sumaríssimo), 22 (videoconf), 29 (videoconf sumaríssimo)
 *   UNA .......................... 5, 19 (sumaríssimo), 23 (videoconf), 31 (videoconf sumaríssimo)
 *   Instrução .................... 6, 12 (sumaríssimo), 24 (videoconf), 27 (videoconf sumaríssimo)
 *   Encerramento de Instrução .... 10, 25 (videoconf)
 *   Julgamento ................... 4
 *
 * TODO(decisão) — tipos que o documento NÃO define regra explícita para. Em vez de arriscar
 * um chute de Efetiva/Adiada, ficam de fora da população avaliada (filtro WHERE de
 * audiencias_realizadas) até decisão do usuário/SETIC:
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
 *
 * Códigos de movimento (pje.tb_evento_processual / tpe.id_evento) confirmados pelo usuário:
 *   Conclusão para sentença ...... 51 (+ ds_texto_final_externo ILIKE '%sentença%')
 *   Prolação de sentença ......... 219, 220, 221, 50110, 50118 (julgamento de mérito, 1º grau)
 *   Homologação de acordo ........ 466 (Homologada a transação)
 *   Expedição ofício/carta precatória/mandado .. 60 (+ ds_texto_final_externo ILIKE por tipo)
 *   Perícia ativa ................ não é movimento em tb_processo_evento; vem de
 *                                  tb_processo_pericia (query do painel de perícias do PAI,
 *                                  fornecida pelo usuário) — status aberto (L/S/A/M) +
 *                                  prazo válido (tb_proc_parte_expediente.dt_prazo_legal_parte
 *                                  >= CURRENT_DATE)
 *
 * ATENÇÃO — achado na query ORIGINAL (não só neste rascunho): os ids 941 e 371 que ela usa
 * como sinal extra de "Efetiva" (`OR e.id_evento IN (941, 371)`) correspondem, pela mesma
 * amostra, a "Declarada a incompetência" (941) e "Acolhida a exceção de incompetência" (371)
 * — nada relacionado a sentença/julgamento. Pode ser intencional (processo resolvido/remetido
 * por incompetência também conta como audiência que cumpriu seu papel), mas vale confirmar
 * com a SETIC antes de decidir se esse sinal entra ou não na v2. Não incluído no rascunho
 * abaixo até essa confirmação.
 *
 * TODO(decisão SETIC) — "Prolação de sentença" hoje só cobre sentença DE MÉRITO (219/220/221/
 * 50110/50118). tb_evento (categorias) confirma que também existem sentenças TERMINATIVAS
 * (extinção sem resolução do mérito): 456 Extinção e subcausas 458/459/461/463/464/465,
 * 454 Indeferimento da petição inicial, 50126 Julgamento antecipado parcial (SEM resolução do
 * mérito). Uma sentença terminativa também encerra a fase de conhecimento — pendente de
 * confirmação com a SETIC se deve contar como "Prolação de sentença" aqui. Não incluída no
 * rascunho por ora.
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

-- TODAS as audiências subsequentes (não só a próxima) designadas para o mesmo processo após a
-- atual. Necessária porque, na bipartição UNA->Instrução, o "Encerramento de Instrução" e o
-- "Julgamento" normalmente NÃO são a audiência imediatamente seguinte (esse lugar já é ocupado
-- pela Instrução) — são audiências posteriores a ela. Uma versão anterior deste rascunho usava
-- só a audiência imediatamente seguinte (LIMIT 1) para checar esses dois sinais, o que os
-- deixava de detectar sempre que houvesse qualquer audiência intermediária. Corrigido aqui.
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

-- Próxima audiência (a imediatamente seguinte, ordem = 1) — usada só para as três checagens que
-- de fato dependem de "qual é a próxima": regra geral de mesma categoria, Inicial->qualquer
-- subsequente, e UNA->Instrução define bipartição.
proxima_audiencia AS (
    SELECT
        id_processo_audiencia,
        id_tipo_audiencia AS id_tipo_audiencia_proxima,
        dt_marcacao
    FROM audiencias_subsequentes
    WHERE ordem = 1
),

-- Data-limite do 3º dia útil após a audiência, calculada a partir de
-- pje.tb_calendario_eventos. Regra definida pelo usuário: dia útil = não suspende
-- audiência E não suspende prazo. Abrangência: nacional (id_orgao_julgador/id_estado
-- IS NULL) ou estado de SP (id_estado = 26).
-- TODO(decisão SETIC): id_municipio não está sendo considerado (regra hoje só cobre nacional
-- + estado de SP). Se um registro do calendário suspender audiência/prazo só num município
-- específico (não no estado inteiro), esse dia deve contar como não-útil apenas para as varas
-- daquele município, ou nacional+estadual já é suficiente?
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
-- Achado (amostra de tb_evento_processual devolvida pelo usuário): ofício, carta precatória
-- e mandado são todos instâncias do MESMO movimento genérico da TPU/CNJ
-- "60 Expedido(a) #{tipo de documento} a(o) #{destinatário}" — o tipo real só existe no texto
-- resolvido (tpe.ds_texto_final_externo), não no catálogo (ds_movimento mantém o placeholder).
-- Por isso o filtro usa o código 60 + ILIKE no texto final, e não mais join com
-- tb_evento/tb_evento_processual.
-- TODO(confirmar): existe tabela de complemento/parâmetro estruturada para "tipo de
-- documento" (mais robusta que ILIKE em texto livre)? Não localizada na amostra devolvida.
--
-- Perícia ativa: query do "painel de perícias do PAI" fornecida pelo usuário (mesma consulta
-- usada tanto para prazo válido quanto vencido — a diferença está em como o prazo é
-- interpretado depois). Aqui só entra a perícia ATIVA (laudo em aberto) com PRAZO VÁLIDO;
-- prazo vencido segue as regras do painel de perícias do PAI (fora de escopo, conforme já
-- definido na seção 2.5/regra 5 do cabeçalho deste arquivo).
-- TODO(confirmar): a janela de 3 dias úteis se aplica à DATA DE MARCAÇÃO da perícia
-- (pp.dt_marcacao), como para os demais diligências? Diferente de expedição de documento
-- (ato pontual), perícia é um estado contínuo — pode fazer mais sentido contar como "ativa"
-- independente de quando foi marcada, desde que aberta e com prazo válido na data de
-- referência. Mantido com o mesmo critério de janela por consistência com os outros
-- movimentos, até confirmação.
-- Decidido pelo usuário: referência de "prazo válido" = CURRENT_DATE - 1 dia, igual à "Data de
-- referência do relatório" do painel de perícias original.
movimentos_diligencia AS (
    SELECT DISTINCT r.id_processo_audiencia
    FROM audiencias_realizadas r
    INNER JOIN calendario_3du cal ON cal.id_processo_audiencia = r.id_processo_audiencia
    INNER JOIN pje.tb_processo_evento tpe ON tpe.id_processo = r.num_proc_id_origem
    WHERE tpe.dt_atualizacao BETWEEN date_trunc('day', r.dta_audiencia::date)
        AND cal.limite_3_dias_uteis + INTERVAL '1 day' - INTERVAL '1 second'
        AND tpe.id_evento = 60 -- Expedido(a) #{tipo de documento} a(o) #{destinatário}
        AND tpe.ds_texto_final_externo ILIKE ANY (ARRAY[
            '%Ofício%', '%Carta Precatória%', '%Mandado%'
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

-- Encerramento de Instrução designado dentro da janela de 3 dias úteis — checagem GERAL
-- (qualquer audiência subsequente desse tipo dentro da janela, via audiencias_subsequentes),
-- não só "a próxima". Na bipartição UNA->Instrução, o Encerramento normalmente vem DEPOIS da
-- Instrução (que já ocupa o lugar de "próxima"), então checar só proxima_audiencia (como uma
-- versão anterior deste rascunho fazia) nunca encontraria esse sinal.
-- Achado na releitura do documento: a linha "A designação de Encerramento de Instrução é
-- obrigatória quando há diligências pendentes" confirma que esse sinal é EXIGIDO junto com a
-- diligência para o resultado Efetiva — não bastava checar só a diligência, como o rascunho
-- anterior fazia (corrigido abaixo, no CASE de classificacao).
encerramento_instrucao_na_janela AS (
    SELECT DISTINCT s.id_processo_audiencia
    FROM audiencias_subsequentes s
    CROSS JOIN parametros p
    INNER JOIN calendario_3du cal ON cal.id_processo_audiencia = s.id_processo_audiencia
    WHERE s.id_tipo_audiencia = ANY (p.tipo_encerramento_instrucao)
      AND s.dt_marcacao <= cal.limite_3_dias_uteis
),

-- Movimentos de encerramento (conclusão/prolação de sentença, homologação de
-- acordo, marcação de julgamento) em até 3 dias úteis.
-- Achados (amostra de tb_evento_processual/tb_evento):
--   - Conclusão para sentença: código 51 "Conclusos os autos para #{tipo de conclusão}...",
--     igual à lógica já usada na query original (texto resolvido contendo "sentença").
--   - Prolação de sentença: não existe como movimento literal; o julgamento de mérito em
--     1º grau aparece como resultado específico — códigos 219 (procedente), 220
--     (improcedente), 221 (procedente em parte), 50110 (julgado antecipadamente parte do
--     mérito), 50118 (liminarmente improcedente).
--   - Homologação de acordo: não existe como texto literal "homologação de acordo"; o termo
--     técnico trabalhista usado é "transação" — código 466 "Homologada a transação".
--   - Marcação de audiência de julgamento: QUALQUER audiência subsequente desse tipo dentro da
--     janela (via audiencias_subsequentes), mesmo raciocínio do Encerramento de Instrução acima
--     — corrigido; a versão anterior só olhava a audiência imediatamente seguinte.
-- TODO(decisão SETIC): "Prolação de sentença" hoje só cobre sentença DE MÉRITO. Existem
-- também candidatos a sentença TERMINATIVA (extinção sem resolução do mérito), não incluídos
-- até confirmação: 456 (Extinção) e subcausas 458/459/461/463/464/465, 454 (Indeferimento da
-- petição inicial), 50126 (Julgamento antecipado parcial SEM resolução do mérito).
movimentos_julgamento AS (
    SELECT DISTINCT r.id_processo_audiencia
    FROM audiencias_realizadas r
    INNER JOIN calendario_3du cal ON cal.id_processo_audiencia = r.id_processo_audiencia
    INNER JOIN pje.tb_processo_evento tpe ON tpe.id_processo = r.num_proc_id_origem
    WHERE tpe.dt_atualizacao BETWEEN date_trunc('day', r.dta_audiencia::date)
        AND cal.limite_3_dias_uteis + INTERVAL '1 day' - INTERVAL '1 second'
        AND (
            (tpe.id_evento = 51 AND tpe.ds_texto_final_externo ILIKE '%sentença%') -- Conclusão p/ sentença
            OR tpe.id_evento IN (219, 220, 221, 50110, 50118) -- Prolação de sentença (mérito)
            -- OR tpe.id_evento IN (456, 458, 459, 461, 463, 464, 465, 454, 50126) -- sentença terminativa (TODO decisão SETIC)
            OR tpe.id_evento = 466 -- Homologada a transação (homologação de acordo)
        )

    UNION

    SELECT DISTINCT s.id_processo_audiencia
    FROM audiencias_subsequentes s
    CROSS JOIN parametros p
    INNER JOIN calendario_3du cal ON cal.id_processo_audiencia = s.id_processo_audiencia
    WHERE s.id_tipo_audiencia = ANY (p.tipo_julgamento)
      AND s.dt_marcacao <= cal.limite_3_dias_uteis
),

classificacao AS (
    SELECT
        r.*,
        CASE
            -- 1) Regra geral: redesignação da MESMA CATEGORIA. Agrupa variantes sumaríssimo/
            --    videoconferência via os arrays de parametros — uma versão anterior deste
            --    rascunho comparava o id exato (pa.id_tipo_audiencia_proxima = r.id_tipo_audiencia),
            --    o que deixava passar despercebido, por exemplo, UNA presencial seguida de UNA
            --    por videoconferência (ids diferentes, mesma categoria). Corrigido aqui.
            WHEN (r.id_tipo_audiencia = ANY (p.tipo_inicial) AND pa.id_tipo_audiencia_proxima = ANY (p.tipo_inicial))
              OR (r.id_tipo_audiencia = ANY (p.tipo_una) AND pa.id_tipo_audiencia_proxima = ANY (p.tipo_una))
              OR (r.id_tipo_audiencia = ANY (p.tipo_instrucao) AND pa.id_tipo_audiencia_proxima = ANY (p.tipo_instrucao))
                THEN 'Adiada'

            -- 2) Audiência Inicial: qualquer subsequente conta como efetiva
            WHEN r.id_tipo_audiencia = ANY (p.tipo_inicial)
                 AND pa.id_tipo_audiencia_proxima IS NOT NULL THEN 'Efetiva'

            -- 3) UNA -> Instrução (bipartição). "Efetiva" por diligência exige TAMBÉM
            --    Encerramento de Instrução designado (linha do documento: "A designação de
            --    Encerramento de Instrução é obrigatória quando há diligências pendentes") —
            --    não basta a diligência sozinha, como uma versão anterior deste rascunho fazia.
            WHEN r.id_tipo_audiencia = ANY (p.tipo_una)
                 AND pa.id_tipo_audiencia_proxima = ANY (p.tipo_instrucao)
                 AND md.id_processo_audiencia IS NOT NULL
                 AND enc.id_processo_audiencia IS NOT NULL
                THEN 'Efetiva'
            WHEN r.id_tipo_audiencia = ANY (p.tipo_una)
                 AND pa.id_tipo_audiencia_proxima = ANY (p.tipo_instrucao)
                 AND md.id_processo_audiencia IS NULL
                 AND mj.id_processo_audiencia IS NOT NULL THEN 'Efetiva'
            WHEN r.id_tipo_audiencia = ANY (p.tipo_una)
                 AND pa.id_tipo_audiencia_proxima = ANY (p.tipo_instrucao)
                 THEN 'Adiada' -- bipartição injustificada (cobre inclusive diligência SEM
                                -- Encerramento de Instrução designado, que cai aqui por
                                -- eliminação das duas condições acima)

            -- 4) Instrução — mesma lógica de exigir Encerramento de Instrução junto com a
            --    diligência ("Mesmos critérios aplicados à audiência UNA", conforme o documento).
            WHEN r.id_tipo_audiencia = ANY (p.tipo_instrucao)
                 AND md.id_processo_audiencia IS NOT NULL
                 AND enc.id_processo_audiencia IS NOT NULL
                THEN 'Efetiva'
            WHEN r.id_tipo_audiencia = ANY (p.tipo_instrucao)
                 AND md.id_processo_audiencia IS NULL
                 AND mj.id_processo_audiencia IS NOT NULL THEN 'Efetiva'

            -- TODO(decisão SETIC): o documento não define o que acontece quando UNA é seguida
            -- de um tipo que não é UNA nem Instrução (ex.: Encerramento de Instrução ou
            -- Julgamento diretamente, pulando a Instrução), nem o que acontece com Instrução
            -- quando nem diligência+Encerramento nem "sem diligência+Julgamento" se aplicam.
            -- Ambos os casos caem aqui por omissão (Adiada) — ver seção 2 do doc de análise.
            ELSE 'Adiada'
        END AS status
    FROM audiencias_realizadas r
    CROSS JOIN parametros p
    LEFT JOIN proxima_audiencia pa ON pa.id_processo_audiencia = r.id_processo_audiencia
    LEFT JOIN movimentos_diligencia md ON md.id_processo_audiencia = r.id_processo_audiencia
    LEFT JOIN movimentos_julgamento mj ON mj.id_processo_audiencia = r.id_processo_audiencia
    LEFT JOIN encerramento_instrucao_na_janela enc ON enc.id_processo_audiencia = r.id_processo_audiencia
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
