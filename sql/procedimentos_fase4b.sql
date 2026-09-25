/*
 * FASE 4B: Procedimentos para Popular Tabelas de Monitoramento
 *
 * Objetivo: Implementar procedures para:
 * 1. Executar query v2 e inserir resultados em fato_audiencia_classificada (com UPSERT para dedup)
 * 2. Registrar execução em trilha_execucao com metadados
 * 3. Atualizar metrica_integridade com KPIs
 *
 * Uso:
 * - Fase 3 (Testes): Usar sp_executar_classificacao() para validar queries
 * - Fase 4c (Monitoramento): Integrar em job/schedule
 * - Fase 5 (Produção): Invocar via cron/Airflow/job agendado
 *
 * Bloqueador Fase 4d: Decisão SETIC #10 sobre watermark (rolling window vs. config table)
 * → seção no final deste arquivo cobre ambas as opções
 */

-- ============================================================================
-- PROCEDURE 1: sp_executar_classificacao
-- ============================================================================
-- Executa query v2 completa e insere em fato_audiencia_classificada com UPSERT
--
-- Parâmetros:
--   p_versao_regra (default '2.0'): versão da regra para rastreamento
--   p_origem ('INICIAL'|'REPROCESSAMENTO'|'CORRECAO'): contexto da execução
--   p_usuario (default session_user): quem rodou
--
-- Retorna:
--   qtd_processadas, qtd_efetivas, qtd_adiadas, tempo_ms, status
--
-- Comportamento:
--   - Lê VAR_ULT_DT_AUDIENCIA de pai_2_0.audiencias (autorreferente, por enquanto)
--   - Executa query v2 com WHERE dt_inicio > VAR_ULT_DT_AUDIENCIA
--   - UPSERT em fato_audiencia_classificada (id_processo_audiencia, versao_regra)
--   - Calcula hash_condicoes_sinal para detectar mudanças silenciosas
--   - Insere trilha_execucao com metadados
--   - Se SETIC responde sobre rolling window: modificar VAR_ULT_DT_AUDIENCIA conforme
--

CREATE OR REPLACE PROCEDURE pai_2_0.sp_executar_classificacao(
    p_versao_regra TEXT DEFAULT '2.0',
    p_origem TEXT DEFAULT 'INICIAL',
    p_usuario TEXT DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_timestamp_inicio TIMESTAMP WITH TIME ZONE;
    v_timestamp_fim TIMESTAMP WITH TIME ZONE;
    v_duracao_ms NUMERIC;
    v_qtd_processadas INT := 0;
    v_qtd_efetivas INT := 0;
    v_qtd_adiadas INT := 0;
    v_watermark_entrada DATE;
    v_watermark_saida DATE;
    v_id_execucao UUID;
    v_status TEXT;
BEGIN
    v_timestamp_inicio := CURRENT_TIMESTAMP;
    v_id_execucao := gen_random_uuid();
    v_usuario := COALESCE(p_usuario, session_user);
    v_status := 'INICIADA';

    BEGIN
        -- PASSO 1: Determinar watermark de entrada
        -- NOTA: Implementação atual (autorreferente). Ver seção "Decisão SETIC #10" ao final
        SELECT MAX(dt_audiencia) INTO v_watermark_entrada
        FROM pai_2_0.audiencias
        WHERE status <> 'Programada';

        IF v_watermark_entrada IS NULL THEN
            v_watermark_entrada := '2000-01-01'::DATE;
        END IF;

        -- PASSO 2: Executar query v2 e inserir com UPSERT
        -- (Simulado aqui com INSERT ... ON CONFLICT)
        INSERT INTO pai_2_0.fato_audiencia_classificada (
            id_processo_audiencia,
            versao_regra,
            classificacao,
            motivo_classificacao,
            flg_incompetencia,
            flg_inicial_com_subsequente,
            flg_mesma_categoria_redesignada,
            flg_una_bipartite,
            flg_diligencia_na_janela,
            flg_encerramento_instrucao_na_janela,
            flg_julgamento_na_janela,
            flg_tipo8_instrucao_julgamento,
            flg_pericias_ativas_na_janela,
            data_calculo,
            hash_condicoes_sinal
        )
        -- TODO: Substituir este placeholder por SELECT da query v2 real
        -- Este é um exemplo de como integrar a query v2
        -- Quando query v2 estiver finalizada, substituir este SELECT por:
        -- SELECT id_processo_audiencia, versao_regra, classificacao, motivo_classificacao, ...
        --   FROM (
        --       [CONTEÚDO COMPLETO DE audiencias_realizadas_v2_draft.sql]
        --   ) v2
        --   WHERE date_trunc('day', dta_audiencia) > v_watermark_entrada
        SELECT
            1 AS id_processo_audiencia,
            p_versao_regra AS versao_regra,
            'Efetiva' AS classificacao,
            'EXEMPLO: Query não implementada ainda' AS motivo_classificacao,
            FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE,
            CURRENT_TIMESTAMP,
            MD5('dummy')
        WHERE FALSE -- Placeholder: nenhuma linha até query v2 estar pronta
        ON CONFLICT (id_processo_audiencia, versao_regra)
        DO UPDATE SET
            classificacao = EXCLUDED.classificacao,
            motivo_classificacao = EXCLUDED.motivo_classificacao,
            flg_incompetencia = EXCLUDED.flg_incompetencia,
            flg_inicial_com_subsequente = EXCLUDED.flg_inicial_com_subsequente,
            flg_mesma_categoria_redesignada = EXCLUDED.flg_mesma_categoria_redesignada,
            flg_una_bipartite = EXCLUDED.flg_una_bipartite,
            flg_diligencia_na_janela = EXCLUDED.flg_diligencia_na_janela,
            flg_encerramento_instrucao_na_janela = EXCLUDED.flg_encerramento_instrucao_na_janela,
            flg_julgamento_na_janela = EXCLUDED.flg_julgamento_na_janela,
            flg_tipo8_instrucao_julgamento = EXCLUDED.flg_tipo8_instrucao_julgamento,
            flg_pericias_ativas_na_janela = EXCLUDED.flg_pericias_ativas_na_janela,
            data_calculo = EXCLUDED.data_calculo,
            hash_condicoes_sinal = EXCLUDED.hash_condicoes_sinal,
            nro_reprocessamento = nro_reprocessamento + 1,
            data_ult_reprocessamento = CURRENT_TIMESTAMP;

        GET DIAGNOSTICS v_qtd_processadas = ROW_COUNT;

        -- Contar resultados
        SELECT
            COUNT(*),
            SUM(CASE WHEN classificacao = 'Efetiva' THEN 1 ELSE 0 END),
            SUM(CASE WHEN classificacao = 'Adiada' THEN 1 ELSE 0 END)
        INTO v_qtd_processadas, v_qtd_efetivas, v_qtd_adiadas
        FROM pai_2_0.fato_audiencia_classificada
        WHERE versao_regra = p_versao_regra
          AND data_calculo >= v_timestamp_inicio;

        -- Determinar watermark de saída
        SELECT MAX(dt_audiencia) INTO v_watermark_saida
        FROM pai_2_0.audiencias
        WHERE status <> 'Programada';

        v_status := 'SUCESSO';

    EXCEPTION WHEN OTHERS THEN
        v_status := 'FALHA: ' || SQLERRM;
        RAISE WARNING 'Erro em sp_executar_classificacao: %', SQLERRM;
    END;

    -- PASSO 3: Registrar execução em trilha_execucao
    v_timestamp_fim := CURRENT_TIMESTAMP;
    v_duracao_ms := EXTRACT(EPOCH FROM (v_timestamp_fim - v_timestamp_inicio)) * 1000;

    INSERT INTO pai_2_0.trilha_execucao (
        id_execucao,
        dt_execucao,
        usuario,
        origem,
        versao_regra,
        qtd_audiencias_processadas,
        qtd_classificadas_efetiva,
        qtd_classificadas_adiada,
        watermark_entrada_dt_audiencia,
        watermark_saida_dt_audiencia,
        duracao_ms,
        status,
        reprocessa_apos_dias
    )
    VALUES (
        v_id_execucao,
        v_timestamp_fim,
        v_usuario,
        p_origem,
        p_versao_regra,
        v_qtd_processadas,
        v_qtd_efetivas,
        v_qtd_adiadas,
        v_watermark_entrada,
        v_watermark_saida,
        v_duracao_ms,
        v_status,
        45 -- Rolling window padrão (se SETIC confirmar Opção A)
    );

    -- PASSO 4: Atualizar metrica_integridade
    CALL pai_2_0.sp_atualizar_metricas_integridade(p_versao_regra);

    -- Retornar resumo (compatível com Airflow/job scheduler)
    RAISE NOTICE 'Execução % concluída: processadas=%, efetivas=%, adiadas=%, ms=%',
        v_id_execucao, v_qtd_processadas, v_qtd_efetivas, v_qtd_adiadas, v_duracao_ms;

END;
$$;

-- ============================================================================
-- PROCEDURE 2: sp_atualizar_metricas_integridade
-- ============================================================================
-- Calcula KPIs e detecta regressões comparando duas últimas execuções
--
-- Chamada automaticamente por sp_executar_classificacao
-- Insere/atualiza row em metrica_integridade

CREATE OR REPLACE PROCEDURE pai_2_0.sp_atualizar_metricas_integridade(
    p_versao_regra TEXT DEFAULT '2.0'
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_pct_efetiva NUMERIC;
    v_pct_regressao NUMERIC;
    v_status_alerta TEXT;
    v_data_ultima_execucao TIMESTAMP WITH TIME ZONE;
    v_qtd_efetiva INT;
    v_qtd_total INT;
BEGIN
    -- Calcular KPIs da última execução
    SELECT
        tr.dt_execucao,
        tr.qtd_classificadas_efetiva,
        tr.qtd_audiencias_processadas,
        ROUND(100.0 * tr.qtd_classificadas_efetiva / NULLIF(tr.qtd_audiencias_processadas, 0), 2)
    INTO
        v_data_ultima_execucao,
        v_qtd_efetiva,
        v_qtd_total,
        v_pct_efetiva
    FROM pai_2_0.trilha_execucao tr
    WHERE tr.versao_regra = p_versao_regra
      AND tr.status = 'SUCESSO'
    ORDER BY tr.dt_execucao DESC
    LIMIT 1;

    IF v_data_ultima_execucao IS NULL THEN
        RETURN; -- Nenhuma execução bem-sucedida ainda
    END IF;

    -- Calcular regressão comparando com penúltima execução
    WITH ult_exec AS (
        SELECT
            ROW_NUMBER() OVER (ORDER BY dt_execucao DESC) AS rn,
            dt_execucao,
            qtd_classificadas_efetiva,
            qtd_audiencias_processadas,
            100.0 * qtd_classificadas_efetiva / NULLIF(qtd_audiencias_processadas, 0) AS pct_efetiva
        FROM pai_2_0.trilha_execucao
        WHERE versao_regra = p_versao_regra
          AND status = 'SUCESSO'
        LIMIT 2
    )
    SELECT
        ROUND(
            (ult_exec_atual.pct_efetiva - ult_exec_anterior.pct_efetiva),
            2
        )
    INTO v_pct_regressao
    FROM (SELECT * FROM ult_exec WHERE rn = 1) ult_exec_atual
    CROSS JOIN (SELECT * FROM ult_exec WHERE rn = 2) ult_exec_anterior;

    -- Determinar status de alerta
    IF v_pct_regressao IS NULL THEN
        v_status_alerta := 'OK'; -- Primeira execução
    ELSIF v_pct_regressao < -5 THEN
        v_status_alerta := 'ALERTA: Regressão > 5%';
    ELSIF v_pct_regressao < -2 THEN
        v_status_alerta := 'AVISO: Regressão > 2%';
    ELSE
        v_status_alerta := 'OK';
    END IF;

    -- Inserir/atualizar metrica_integridade
    INSERT INTO pai_2_0.metrica_integridade (
        versao_regra,
        data_metrica,
        pct_classificadas_efetiva,
        pct_regressao_vs_anterior,
        status_alerta,
        qtd_registros_monitorados,
        observacoes
    )
    VALUES (
        p_versao_regra,
        v_data_ultima_execucao,
        v_pct_efetiva,
        v_pct_regressao,
        v_status_alerta,
        v_qtd_total,
        CASE
            WHEN v_status_alerta = 'OK' THEN 'Métrica estável'
            WHEN v_status_alerta LIKE 'ALERTA%' THEN 'Investigar possível regressão'
            WHEN v_status_alerta LIKE 'AVISO%' THEN 'Monitor próxima execução'
            ELSE 'Primeira execução'
        END
    )
    ON CONFLICT (versao_regra, data_metrica)
    DO UPDATE SET
        pct_classificadas_efetiva = EXCLUDED.pct_classificadas_efetiva,
        pct_regressao_vs_anterior = EXCLUDED.pct_regressao_vs_anterior,
        status_alerta = EXCLUDED.status_alerta,
        qtd_registros_monitorados = EXCLUDED.qtd_registros_monitorados,
        observacoes = EXCLUDED.observacoes;

    RAISE NOTICE 'Métricas atualizadas: versao=%, pct_efetiva=%, status=%',
        p_versao_regra, v_pct_efetiva, v_status_alerta;

END;
$$;

-- ============================================================================
-- PROCEDURE 3: sp_validar_integridade_dados
-- ============================================================================
-- Auditoria: compara v1 vs v2 para detectar perda silenciosa de dados
--
-- Chamada por:
-- - Fase 3: validação manual antes de aprovação
-- - Fase 4c: comparação periódica (ex.: diária)
--
-- Lógica:
--   1. Contar audiências em v1 (query original)
--   2. Contar audiências em v2 (query nova)
--   3. Se delta > 0.5%, sinalizar ALERTA (possível perda de dados)
--   4. Comparar % Efetiva v1 vs v2 (se delta > 2%, regressão suspeita)

CREATE OR REPLACE PROCEDURE pai_2_0.sp_validar_integridade_dados(
    p_versao_regra TEXT DEFAULT '2.0'
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_qtd_v1 INT;
    v_qtd_v2 INT;
    v_pct_v1 NUMERIC;
    v_pct_v2 NUMERIC;
    v_delta_qtd NUMERIC;
    v_delta_pct NUMERIC;
    v_status_alerta TEXT;
BEGIN
    -- TODO: Implementar após query v1 original estar disponível
    -- Por enquanto, este é um template

    RAISE NOTICE 'Validação de integridade: comparação v1 vs v2 (TODO implementar)';

    /*
    -- Simulação da lógica (quando query v1 estiver disponível):
    SELECT COUNT(*), 100.0 * SUM(CASE WHEN classificacao='Efetiva' THEN 1 ELSE 0 END) / COUNT(*)
    INTO v_qtd_v1, v_pct_v1
    FROM pai_2_0.audiencias -- resultado v1 original
    WHERE status <> 'Programada';

    SELECT COUNT(*), 100.0 * SUM(CASE WHEN classificacao='Efetiva' THEN 1 ELSE 0 END) / COUNT(*)
    INTO v_qtd_v2, v_pct_v2
    FROM pai_2_0.fato_audiencia_classificada
    WHERE versao_regra = p_versao_regra
      AND nro_reprocessamento = 1; -- Apenas primeira rodada (não reprocessadas)

    v_delta_qtd := ROUND(100.0 * ABS(v_qtd_v1 - v_qtd_v2) / NULLIF(v_qtd_v1, 0), 2);
    v_delta_pct := ROUND(ABS(v_pct_v1 - v_pct_v2), 2);

    IF v_delta_qtd > 0.5 THEN
        v_status_alerta := 'CRÍTICO: Perda de dados v1->v2 (' || v_delta_qtd || '%)';
    ELSIF v_delta_pct > 2 THEN
        v_status_alerta := 'ALERTA: Regressão de % Efetiva (' || v_delta_pct || '%)';
    ELSE
        v_status_alerta := 'OK: Validação passou';
    END IF;

    RAISE NOTICE 'v1: %, v2: %, delta: %, status: %',
        v_qtd_v1, v_qtd_v2, v_delta_qtd, v_status_alerta;
    */

END;
$$;

-- ============================================================================
-- DECISÃO SETIC #10: Reprocessamento e Watermark
-- ============================================================================
/*
 * OPÇÃO A: Rolling Window (RECOMENDADO)
 * Implementação:
 *
 * 1. Modificar sp_executar_classificacao para usar:
 *    SELECT MAX(dt_audiencia) - INTERVAL '45 days' INTO v_watermark_entrada
 *    FROM pai_2_0.audiencias
 *    WHERE status <> 'Programada';
 *
 * 2. Sempre reprocessa últimos 45 dias (cobre 3DU + recesso)
 * 3. Detecta automaticamente lacunas (audiências não reprocessadas antes)
 * 4. UPSERT em fato_audiencia_classificada garante dedup por (id_processo_audiencia, versao_regra)
 *
 * Custo: +5-10% de I/O (reprocessa 45 dias toda execução)
 * Benefício: Seguro, detecta e corrige automaticamente
 *
 * ---
 *
 * OPÇÃO B: Marca d'Água Externa
 * Implementação:
 *
 * 1. Criar tabela config_watermark:
 *    CREATE TABLE pai_2_0.config_watermark (
 *      versao_regra TEXT PRIMARY KEY,
 *      dt_ultima_processada TIMESTAMP,
 *      dt_atualizado TIMESTAMP DEFAULT CURRENT_TIMESTAMP
 *    );
 *
 * 2. Modificar sp_executar_classificacao para:
 *    SELECT dt_ultima_processada INTO v_watermark_entrada
 *    FROM pai_2_0.config_watermark
 *    WHERE versao_regra = p_versao_regra;
 *
 *    [executar query v2...]
 *
 *    UPDATE pai_2_0.config_watermark
 *    SET dt_ultima_processada = MAX(dt_audiencia_processada),
 *        dt_atualizado = CURRENT_TIMESTAMP
 *    WHERE versao_regra = p_versao_regra;
 *
 * Custo: Sem reprocessamento desnecessário (apenas > watermark)
 * Benefício: Explícito e auditável
 * Desvantagem: Requer sincronismo entre query e UPDATE
 *
 * ---
 *
 * TODO: Implementar Opção A como padrão (simples, segura)
 * Aguardar resposta SETIC para confirmar escolha
 */

-- ============================================================================
-- UTILIDADES: Limpeza de Dados (teste)
-- ============================================================================
-- Função helper para DEV/QA: limpar fato_audiencia_classificada e reprocessar tudo

CREATE OR REPLACE PROCEDURE pai_2_0.sp_limpar_fato_audiencia_classificada()
LANGUAGE plpgsql
AS $$
BEGIN
    DELETE FROM pai_2_0.fato_audiencia_classificada;
    DELETE FROM pai_2_0.trilha_execucao;
    DELETE FROM pai_2_0.metrica_integridade;
    RAISE NOTICE 'Tabelas de monitoramento limpas. Próximo: executar sp_executar_classificacao()';
END;
$$;

-- ============================================================================
-- Índices para Performance
-- ============================================================================
-- (Já criados em tabelas_monitoramento_fase4.sql)
-- Manter sincronizados: idx_fato_classificacao, idx_fato_versao, idx_fato_data

