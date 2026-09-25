/*
 * FASE 4: Tabelas de Monitoramento e Auditoria
 *
 * Objetivo: Rastrear classificações de audiências, mudanças de versão de regra,
 * integridade de dados e histórico de execução.
 *
 * Tabelas:
 * 1. fato_audiencia_classificada: Fato com cada classificação produzida
 * 2. trilha_execucao: Log estruturado de cada rodada de processamento
 * 3. metrica_integridade: Métricas de QA calculadas por execução
 * 4. mapeamento_tipos_audiencia: Catálogo para debug (referência)
 *
 * Motivo da estrutura:
 * - fato_audiencia_classificada pode ser enorme (~2M+ registros em produção)
 *   então usa chave simples (id_processo_audiencia, versao_regra) para dedup
 * - trilha_execucao registra cada rodada (quando, quem, quantas classificadas)
 * - metrica_integridade calcula KPIs (ex.: % regressão vs. versão anterior)
 * - mapeamento_tipos_audiencia é referência estática para queries de debug
 *
 * Implementação em fases:
 * - Fase 4a: Criação das tabelas (este arquivo)
 * - Fase 4b: Trigger ou procedure para popular fato_audiencia_classificada
 * - Fase 4c: Dashboard/queries de monitoramento
 * - Fase 4d: Alertas (ex.: regressão > 5%, perda de dados)
 *
 * CRÍTICO — Bloqueador Fase 4d (não bloqueia 4a-4c):
 * TODO(decisão SETIC #10): se VAR_ULT_DT_AUDIENCIA for mantido como watermark
 * autorreferente, implementar reprocessamento/upsert por (id_processo_audiencia,
 * versao_regra) — ver docs/analise, seção 6. Sem isso, há risco silencioso de
 * perda de dados.
 */

-- ============================================================================
-- TABELA 1: fato_audiencia_classificada
-- ============================================================================
-- Armazena CADA classificação produzida pela query v2.
-- Chave: (id_processo_audiencia, versao_regra)
--   → permite rastrear mudanças de regra (ex.: v2.0 vs v2.1)
--   → permite reprocessamento por upsert (não duplica se re-rodado)
--
-- Colunas críticas:
--   - data_calculo: quando foi calculado (auditoria, reprocessamento)
--   - hash_condicoes_sinal: hash MD5 de (UNA+Instrução+Julgamento+...)
--     para detectar mudanças silenciosas de regra sem mudança de versao_regra
--   - motivo_classificacao: texto descrevendo qual regra gatilhou
--     (ex.: "Regra 2: Inicial → UNA subsequente")

CREATE TABLE IF NOT EXISTS pai_2_0.fato_audiencia_classificada (
    -- Chave de deduplicação
    id_processo_audiencia INT NOT NULL,
    versao_regra TEXT NOT NULL DEFAULT '2.0',

    -- Classificação
    classificacao TEXT NOT NULL CHECK (classificacao IN ('Efetiva', 'Adiada')),
    motivo_classificacao TEXT,

    -- Rastreamento de sinais (para auditoria)
    flg_incompetencia BOOLEAN DEFAULT FALSE, -- Regra 0: 941 ou 371
    flg_inicial_com_subsequente BOOLEAN DEFAULT FALSE, -- Regra 2
    flg_mesma_categoria_redesignada BOOLEAN DEFAULT FALSE, -- Regra 1
    flg_una_bipartite BOOLEAN DEFAULT FALSE, -- Regra 3: UNA → Instrução
    flg_diligencia_na_janela BOOLEAN DEFAULT FALSE, -- Regra 3/4
    flg_encerramento_instrucao_na_janela BOOLEAN DEFAULT FALSE, -- Regra 3a/4
    flg_julgamento_na_janela BOOLEAN DEFAULT FALSE, -- Regra 3b/4
    flg_tipo8_instrucao_julgamento BOOLEAN DEFAULT FALSE, -- Regra 6
    flg_pericias_ativas_na_janela BOOLEAN DEFAULT FALSE, -- Regra 5

    -- Metadata
    data_calculo TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    hash_condicoes_sinal TEXT, -- MD5(concat(flg_*)) para detectar mudanças silenciosas

    -- Reprocessamento (se implementado com base em decisão SETIC #10)
    nro_reprocessamento INT DEFAULT 1,
    data_ult_reprocessamento TIMESTAMP WITH TIME ZONE,

    -- Constraints
    PRIMARY KEY (id_processo_audiencia, versao_regra)
);

-- Índices para queries comuns
CREATE INDEX IF NOT EXISTS idx_fato_classificacao ON pai_2_0.fato_audiencia_classificada (classificacao);
CREATE INDEX IF NOT EXISTS idx_fato_versao ON pai_2_0.fato_audiencia_classificada (versao_regra, data_calculo DESC);
CREATE INDEX IF NOT EXISTS idx_fato_data ON pai_2_0.fato_audiencia_classificada (data_calculo DESC);

-- ============================================================================
-- TABELA 2: trilha_execucao
-- ============================================================================
-- Log estruturado de cada rodada de processamento (carga, reprocessamento).
-- Uma linha por execução da query v2.
--
-- Colunas críticas:
--   - id_execucao: UUID único para rastreabilidade
--   - usuario / sessao: quem/como rodou (cron vs. manual)
--   - qtd_processadas, qtd_efetivas, qtd_adiadas: volume por execução
--   - watermark_entrada / watermark_saida: controle de dados (anti-perda)
--   - duracao_ms: para acompanhar degradação de performance
--   - status: SUCESSO/FALHA/PARCIAL (útil para alertas)

CREATE TABLE IF NOT EXISTS pai_2_0.trilha_execucao (
    -- Identificação da execução
    id_execucao UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    versao_regra TEXT NOT NULL DEFAULT '2.0',
    dt_execucao TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- Quem/Como rodou
    usuario TEXT, -- pessoa ou 'SCHEDULER'
    sessao_id TEXT, -- session_id da aplicação ou NULL se cron
    origem_execucao TEXT CHECK (origem_execucao IN ('MANUAL', 'CRON', 'REPROCESSAMENTO')),

    -- Volume processado
    qtd_audiencias_processadas INT,
    qtd_classificadas_efetiva INT,
    qtd_classificadas_adiada INT,

    -- Controle de dados (Dúvida #10: watermark)
    watermark_entrada_dt_audiencia TIMESTAMP, -- VAR_ULT_DT_AUDIENCIA usado na rodada
    watermark_saida_dt_audiencia TIMESTAMP, -- MAX(dt_audiencia) após inserção
    qtd_audiencias_antes BIGINT, -- COUNT(*) em fato_audiencia_classificada antes
    qtd_audiencias_depois BIGINT, -- COUNT(*) em fato_audiencia_classificada depois

    -- Performance
    duracao_ms INT,

    -- Resultado
    status TEXT CHECK (status IN ('SUCESSO', 'FALHA', 'PARCIAL')),
    mensagem_erro TEXT,

    -- Reprocessamento
    reprocessa_apos_dias INT, -- sugestão: 45 dias (ver docs/analise, seção 6)

    CONSTRAINT check_volume CHECK (qtd_classificadas_efetiva + qtd_classificadas_adiada = qtd_audiencias_processadas)
);

-- Índices para queries temporais
CREATE INDEX IF NOT EXISTS idx_trilha_data ON pai_2_0.trilha_execucao (dt_execucao DESC);
CREATE INDEX IF NOT EXISTS idx_trilha_versao ON pai_2_0.trilha_execucao (versao_regra, dt_execucao DESC);
CREATE INDEX IF NOT EXISTS idx_trilha_status ON pai_2_0.trilha_execucao (status, dt_execucao DESC);

-- ============================================================================
-- TABELA 3: metrica_integridade
-- ============================================================================
-- Métricas calculadas por execução: regressão, perda de dados, outliers.
-- Uma linha por (execucao, tipo_metrica).
--
-- Colunas críticas:
--   - tipo_metrica: qual métrica está sendo relatada
--   - valor_numerico / percentual: valor calculado
--   - alerta: TRUE se valor ultrapassar limiar
--   - recomendacao: ação sugerida (ex.: "Investigar #dúvida 1")

CREATE TABLE IF NOT EXISTS pai_2_0.metrica_integridade (
    -- Chave composta
    id_execucao UUID NOT NULL,
    tipo_metrica TEXT NOT NULL,

    -- Valor
    valor_numerico NUMERIC(12,2),
    percentual NUMERIC(5,2),
    valor_texto TEXT,

    -- Alertas
    alerta BOOLEAN DEFAULT FALSE,
    limiar_alerta NUMERIC(5,2),
    recomendacao TEXT,

    -- Data
    dt_calculo TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- FK (opcional, para integridade referencial)
    FOREIGN KEY (id_execucao) REFERENCES pai_2_0.trilha_execucao(id_execucao)
        ON DELETE CASCADE
);

-- Índice para queries de alertas
CREATE INDEX IF NOT EXISTS idx_metrica_alerta ON pai_2_0.metrica_integridade (alerta, dt_calculo DESC);
CREATE INDEX IF NOT EXISTS idx_metrica_tipo ON pai_2_0.metrica_integridade (tipo_metrica, dt_calculo DESC);

-- ============================================================================
-- TABELA 4: mapeamento_tipos_audiencia
-- ============================================================================
-- Catálogo estático dos tipos de audiência, atualizado manualmente conforme
-- descobertas de negócio. Referência para validação e debug.
--
-- Mantém o mapeamento documentado em audiencias_realizadas_v2_draft.sql
-- Linhas: uma por cada id_tipo_audiencia confirmado

CREATE TABLE IF NOT EXISTS pai_2_0.mapeamento_tipos_audiencia (
    id_tipo_audiencia INT PRIMARY KEY,
    categoria_regra TEXT NOT NULL, -- 'Inicial' | 'UNA' | 'Instrução' | 'Encerramento' | 'Julgamento' | 'Instrução+Julgamento' | 'Fora do Escopo'
    descricao TEXT,
    variante TEXT, -- 'presencial' | 'sumaríssimo' | 'videoconferência' | 'videoconf_sumaríssimo' | 'RS' | NULL
    status_no_documento TEXT, -- 'Definido' | 'Hipótese (SETIC #2)' | 'Hipótese (SETIC #4)' | 'Fora de Escopo' | 'Não Mapeado'
    data_confirmacao DATE,
    notas TEXT,

    CONSTRAINT check_categoria CHECK (categoria_regra IN (
        'Inicial', 'UNA', 'Instrução', 'Encerramento de Instrução',
        'Julgamento', 'Instrução e Julgamento', 'Fora do Escopo', 'Não Mapeado'
    ))
);

-- ============================================================================
-- DADOS INICIAIS: Mapeamento de Tipos
-- ============================================================================
-- Insere os 36 tipos confirmados (ou em hipótese) do documento
-- Origem: linha 69+ de audiencias_realizadas_v2_draft.sql

INSERT INTO pai_2_0.mapeamento_tipos_audiencia
(id_tipo_audiencia, categoria_regra, descricao, variante, status_no_documento, data_confirmacao, notas)
VALUES
-- Inicial
(3, 'Inicial', 'Audiência Inicial', 'presencial', 'Definido', '2026-09-24', NULL),
(16, 'Inicial', 'Audiência Inicial', 'sumaríssimo', 'Definido', '2026-09-24', NULL),
(22, 'Inicial', 'Audiência Inicial', 'videoconferência', 'Definido', '2026-09-24', NULL),
(29, 'Inicial', 'Audiência Inicial', 'videoconf_sumaríssimo', 'Definido', '2026-09-24', NULL),

-- UNA (Único Negócio de Audiência)
(5, 'UNA', 'UNA', 'presencial', 'Definido', '2026-09-24', NULL),
(19, 'UNA', 'UNA', 'sumaríssimo', 'Definido', '2026-09-24', NULL),
(23, 'UNA', 'UNA', 'videoconferência', 'Definido', '2026-09-24', NULL),
(31, 'UNA', 'UNA', 'videoconf_sumaríssimo', 'Definido', '2026-09-24', NULL),
(7, 'UNA', 'UNA - RS ou Justificação Prévia', 'RS', 'Hipótese (SETIC #9)', '2026-09-24', 'RS confirmado como Rito Sumário'),
(9, 'UNA', 'UNA - RS', 'RS', 'Hipótese (SETIC #9)', '2026-09-24', 'RS confirmado como Rito Sumário'),

-- Instrução
(6, 'Instrução', 'Audiência de Instrução', 'presencial', 'Definido', '2026-09-24', NULL),
(12, 'Instrução', 'Audiência de Instrução', 'sumaríssimo', 'Definido', '2026-09-24', NULL),
(24, 'Instrução', 'Audiência de Instrução', 'videoconferência', 'Definido', '2026-09-24', NULL),
(27, 'Instrução', 'Audiência de Instrução', 'videoconf_sumaríssimo', 'Definido', '2026-09-24', NULL),

-- Encerramento de Instrução
(10, 'Encerramento de Instrução', 'Audiência de Encerramento de Instrução', 'presencial', 'Definido', '2026-09-24', 'Sinal, não população avaliada'),
(25, 'Encerramento de Instrução', 'Audiência de Encerramento de Instrução', 'videoconferência', 'Definido', '2026-09-24', 'Sinal, não população avaliada'),

-- Julgamento
(4, 'Julgamento', 'Audiência de Julgamento', 'presencial', 'Definido', '2026-09-24', 'Sinal, não população avaliada'),

-- Instrução e Julgamento (tipo 8)
(8, 'Instrução e Julgamento', 'Instrução e Julgamento (no mesmo ato)', 'presencial', 'Hipótese (SETIC #4)', '2026-09-24', 'Regra própria: sempre Efetiva'),

-- Fora de Escopo (Conciliação em Conhecimento)
(1, 'Fora do Escopo', 'Conciliação em Conhecimento', NULL, 'Fora de Escopo', '2026-09-24', 'Excluída da população'),
(32, 'Fora do Escopo', 'Conciliação em Conhecimento', NULL, 'Fora de Escopo', '2026-09-24', 'Excluída da população'),
(20, 'Fora do Escopo', 'Conciliação em Conhecimento', NULL, 'Fora de Escopo', '2026-09-24', 'Excluída da população'),
(33, 'Fora do Escopo', 'Conciliação em Conhecimento', NULL, 'Fora de Escopo', '2026-09-24', 'Excluída da população'),

-- Fora de Escopo (Conciliação em Execução)
(2, 'Fora do Escopo', 'Conciliação em Execução', NULL, 'Fora de Escopo', '2026-09-24', 'Excluída da população'),
(34, 'Fora do Escopo', 'Conciliação em Execução', NULL, 'Fora de Escopo', '2026-09-24', 'Excluída da população'),
(36, 'Fora do Escopo', 'Conciliação em Execução', NULL, 'Fora de Escopo', '2026-09-24', 'Excluída da população'),
(21, 'Fora do Escopo', 'Conciliação em Execução', NULL, 'Fora de Escopo', '2026-09-24', 'Excluída da população'),
(35, 'Fora do Escopo', 'Conciliação em Execução', NULL, 'Fora de Escopo', '2026-09-24', 'Excluída da população'),
(37, 'Fora do Escopo', 'Conciliação em Execução', NULL, 'Fora de Escopo', '2026-09-24', 'Excluída da população'),

-- Fora de Escopo (Inquirição de testemunha)
(11, 'Fora do Escopo', 'Inquirição de Testemunha (Juízo Deprecado)', NULL, 'Fora de Escopo', '2026-09-24', 'Excluída da população'),
(26, 'Fora do Escopo', 'Inquirição de Testemunha (Juízo Deprecado)', NULL, 'Fora de Escopo', '2026-09-24', 'Excluída da população'),

-- Fora de Escopo (Justificação Prévia)
(18, 'Fora do Escopo', 'Justificação Prévia', NULL, 'Fora de Escopo', '2026-09-24', 'Excluída da população'),

-- Fora de Escopo (Mediação)
(13, 'Fora do Escopo', 'Mediação', NULL, 'Fora de Escopo', '2026-09-24', 'Excluída da população'),
(14, 'Fora do Escopo', 'Mediação', NULL, 'Fora de Escopo', '2026-09-24', 'Excluída da população'),
(15, 'Fora do Escopo', 'Mediação', NULL, 'Fora de Escopo', '2026-09-24', 'Excluída da população'),
(28, 'Fora do Escopo', 'Mediação', NULL, 'Fora de Escopo', '2026-09-24', 'Excluída da população'),

-- Fora de Escopo (Pública)
(17, 'Fora do Escopo', 'Pública', NULL, 'Fora de Escopo', '2026-09-24', 'Excluída da população'),
(30, 'Fora do Escopo', 'Pública', NULL, 'Fora de Escopo', '2026-09-24', 'Excluída da população')

ON CONFLICT (id_tipo_audiencia) DO UPDATE SET
    categoria_regra = EXCLUDED.categoria_regra,
    variante = EXCLUDED.variante,
    data_confirmacao = EXCLUDED.data_confirmacao,
    notas = EXCLUDED.notas;

-- ============================================================================
-- VIEW 1: Últimas Execuções (para monitoramento rápido)
-- ============================================================================
CREATE OR REPLACE VIEW pai_2_0.v_ultimas_execucoes AS
SELECT
    id_execucao,
    versao_regra,
    dt_execucao,
    usuario,
    origem_execucao,
    qtd_audiencias_processadas,
    qtd_classificadas_efetiva,
    qtd_classificadas_adiada,
    ROUND(100.0 * qtd_classificadas_efetiva / NULLIF(qtd_audiencias_processadas, 0), 2) AS pct_efetiva,
    duracao_ms,
    status,
    watermark_entrada_dt_audiencia,
    watermark_saida_dt_audiencia,
    qtd_audiencias_depois - qtd_audiencias_antes AS delta_registros
FROM pai_2_0.trilha_execucao
ORDER BY dt_execucao DESC
LIMIT 50;

-- ============================================================================
-- VIEW 2: Regressões Potenciais (para alertas)
-- ============================================================================
-- Compara duas últimas execuções: se pct_efetiva caiu >5%, sinaliza alerta
CREATE OR REPLACE VIEW pai_2_0.v_regressoes_potenciais AS
WITH ult2 AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY dt_execucao DESC) AS rn,
        dt_execucao,
        qtd_classificadas_efetiva,
        qtd_audiencias_processadas,
        100.0 * qtd_classificadas_efetiva / NULLIF(qtd_audiencias_processadas, 0) AS pct_efetiva
    FROM pai_2_0.trilha_execucao
    WHERE status = 'SUCESSO'
    LIMIT 2
)
SELECT
    ult2_atual.dt_execucao AS dt_execucao_atual,
    ult2_atual.pct_efetiva AS pct_efetiva_atual,
    ult2_anterior.dt_execucao AS dt_execucao_anterior,
    ult2_anterior.pct_efetiva AS pct_efetiva_anterior,
    ROUND(ult2_atual.pct_efetiva - ult2_anterior.pct_efetiva, 2) AS delta_pct,
    CASE
        WHEN ult2_atual.pct_efetiva - ult2_anterior.pct_efetiva < -5 THEN 'ALERTA: Regressão > 5%'
        WHEN ult2_atual.pct_efetiva - ult2_anterior.pct_efetiva < -2 THEN 'AVISO: Regressão > 2%'
        ELSE 'OK'
    END AS status_alerta
FROM (SELECT * FROM ult2 WHERE rn = 1) ult2_atual
CROSS JOIN (SELECT * FROM ult2 WHERE rn = 2) ult2_anterior;

-- ============================================================================
-- VIEW 3: Distribuição de Classificações por Tipo (debug)
-- ============================================================================
CREATE OR REPLACE VIEW pai_2_0.v_distribuicao_tipos_audiencia AS
SELECT
    m.categoria_regra,
    m.variante,
    COUNT(DISTINCT f.id_processo_audiencia) AS qtd_audiencias,
    SUM(CASE WHEN f.classificacao = 'Efetiva' THEN 1 ELSE 0 END) AS qtd_efetiva,
    SUM(CASE WHEN f.classificacao = 'Adiada' THEN 1 ELSE 0 END) AS qtd_adiada,
    ROUND(100.0 * SUM(CASE WHEN f.classificacao = 'Efetiva' THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_efetiva
FROM pai_2_0.fato_audiencia_classificada f
LEFT JOIN pai_2_0.mapeamento_tipos_audiencia m ON TRUE -- (join necessário depois)
GROUP BY m.categoria_regra, m.variante
ORDER BY qtd_audiencias DESC;

-- ============================================================================
-- Comentários finais
-- ============================================================================
/*
 * Implementação de Reprocessamento (baseado em decisão SETIC #10):
 *
 * Se o watermark VAR_ULT_DT_AUDIENCIA for mantido autorreferente:
 *
 * 1. Após cada execução bem-sucedida, inserir trilha_execucao com:
 *    - watermark_entrada_dt_audiencia = VAR_ULT_DT_AUDIENCIA (usado)
 *    - watermark_saida_dt_audiencia = MAX(dt_audiencia) da query v2
 *    - reprocessa_apos_dias = 45 (conservativo)
 *
 * 2. Criar trigger/procedure que:
 *    - Detecta outliers (gap de 45+ dias com watermark_saida < CURRENT_DATE - 45)
 *    - Reprocessa:
 *      DELETE FROM fato_audiencia_classificada
 *      WHERE data_calculo >= (watermark_saida - 45 dias);
 *      [rodar query v2 com VAR_ULT_DT_AUDIENCIA = watermark_saida - 45]
 *      INSERT ... ON CONFLICT ... DO UPDATE (nro_reprocessamento++)
 *
 * 3. Registrar cada reprocessamento em trilha_execucao com origem='REPROCESSAMENTO'
 *
 * Alternativamente (sem autorreferência):
 * - Usar um repositório de versões (ex.: max(data_calculo) por versao_regra)
 * - Ou usar marca d'água externa (tabela de configuração, não a própria tabela)
 */
