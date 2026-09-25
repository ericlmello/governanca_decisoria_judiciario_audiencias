# Checklist Rápido — Fase 3: Testes

Use este documento como referência rápida durante execução de testes. Para detalhes, ver `docs/PLANO_TESTES_FASE_3.md`.

---

## ⚠️ PRÉ-REQUISITOS

- [ ] Respostas SETIC a dúvidas #1, #3, #5, #6 recebidas
- [ ] Query v2 atualizada com respostas
- [ ] Acesso a banco de dados com ~100k audiências reais
- [ ] Ambiente DEV preparado (schema, permissões)

---

## 🔍 FASE 3.1: Preparação de Dados

```sql
-- 1. Criar tabelas de teste
CREATE TEMP TABLE teste_audiencias AS
SELECT * FROM [query população conforme seção 3, PLANO_TESTES_FASE_3.md];

-- 2. Contar volume
SELECT COUNT(*) FROM teste_audiencias;
-- Esperado: ~100.000

-- 3. Confirmar tipos incluídos
SELECT DISTINCT id_tipo_audiencia FROM teste_audiencias ORDER BY 1;
-- Esperado: apenas [3,16,22,29,5,19,23,31,7,9,6,12,24,27,8]
```

**Checklist:**
- [ ] Volume >= 90k (margem para filtro de datas)
- [ ] Período >= 12 meses
- [ ] Todos os tipos esperados presentes
- [ ] Sem dados corruptos (NULL em colunas críticas)

---

## ▶️ FASE 3.2: Rodar Queries

```sql
-- 1. Query v1 (original)
CREATE TABLE resultado_v1 AS
SELECT 
    id_processo_audiencia,
    classificacao,
    ... [demais colunas]
FROM [query original];

-- 2. Query v2 (nova)
CREATE TABLE resultado_v2 AS
SELECT 
    id_processo_audiencia,
    classificacao,
    motivo_classificacao,
    [demais CTEs]
FROM audiencias_realizadas_v2_draft;

-- 3. Contar por classificação
SELECT 'v1' AS versao, classificacao, COUNT(*) FROM resultado_v1 GROUP BY 2
UNION ALL
SELECT 'v2' AS versao, classificacao, COUNT(*) FROM resultado_v2 GROUP BY 2
ORDER BY 1, 2;
```

**Checklist:**
- [ ] Ambas as queries rodam sem erro
- [ ] v2 retorna ~mesmo volume de v1 (margem: ±2%)
- [ ] % Efetiva em range esperado (verificar com SETIC estimativa)

---

## 📊 FASE 3.3: Identificar Deltas

```sql
-- 1. Comparação direta
WITH diffs AS (
    SELECT 
        COALESCE(v1.id_processo_audiencia, v2.id_processo_audiencia) AS id_aud,
        v1.classificacao AS class_v1,
        v2.classificacao AS class_v2,
        CASE 
            WHEN v1.classificacao IS NULL THEN 'Novo em v2'
            WHEN v2.classificacao IS NULL THEN 'Removido em v2'
            WHEN v1.classificacao = v2.classificacao THEN 'Igual'
            ELSE 'Mudou'
        END AS tipo_delta
    FROM resultado_v1 v1
    FULL OUTER JOIN resultado_v2 v2 USING (id_processo_audiencia)
)
SELECT tipo_delta, COUNT(*) AS qtd, 
       ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM diffs), 2) AS pct
FROM diffs
GROUP BY tipo_delta
ORDER BY qtd DESC;
```

**Checklist:**
- [ ] "Novo em v2" e "Removido em v2" = 0 (ou documentar por quê)
- [ ] "Igual" > 90% (esperado: 90–95%)
- [ ] "Mudou" < 10%

---

## 🎯 FASE 3.4: Analisar Mudanças (Regressões)

```sql
-- 1. Quais mudaram? (Efetiva → Adiada vs. Adiada → Efetiva)
WITH diffs AS (
    SELECT 
        v1.id_processo_audiencia,
        v1.classificacao AS class_v1,
        v2.classificacao AS class_v2,
        v2.motivo_classificacao,
        v1.id_tipo_audiencia,
        v1.dta_audiencia,
        ROW_NUMBER() OVER (ORDER BY v1.dta_audiencia DESC) AS rn
    FROM resultado_v1 v1
    JOIN resultado_v2 v2 USING (id_processo_audiencia)
    WHERE v1.classificacao <> v2.classificacao
)
SELECT class_v1, class_v2, COUNT(*) AS qtd FROM diffs GROUP BY 1, 2 ORDER BY 3 DESC;

-- 2. Amostra de top mudanças
SELECT * FROM diffs WHERE rn <= 100 ORDER BY dta_audiencia DESC;
```

**Checklist para cada mudança significativa (>100 casos):**
- [ ] Documentar o tipo de mudança (Efetiva→Adiada, vice-versa)
- [ ] Verificar `motivo_classificacao` — é consistente?
- [ ] Amostra de IDs para investigação manual

---

## 🔍 FASE 3.5: Investigação Manual (Top Deltas)

Para cada mudança significativa, rodar queries focadas:

### Delta tipo A: Efetiva (v1) → Adiada (v2) — Regressão?

```sql
-- Exemplo: Inicial sem nova audiência (Dúvida #1)
SELECT 
    r.id_processo_audiencia,
    r.nr_processo,
    r.id_tipo_audiencia,
    tta.ds_tipo_audiencia,
    r.dta_audiencia,
    (SELECT COUNT(*) FROM audiencias_subsequentes s 
     WHERE s.id_processo_audiencia = r.id_processo_audiencia) AS qtd_subsequentes,
    (SELECT id_tipo_audiencia FROM audiencias_subsequentes s 
     WHERE s.id_processo_audiencia = r.id_processo_audiencia 
     LIMIT 1) AS tipo_proxima,
    r2.classificacao AS class_v2,
    r2.motivo_classificacao
FROM resultado_v1 r
JOIN resultado_v2 r2 USING (id_processo_audiencia)
LEFT JOIN pje.tb_tipo_audiencia tta ON tta.id_tipo_audiencia = r.id_tipo_audiencia
WHERE r.id_tipo_audiencia = ANY(ARRAY[3,16,22,29]) -- Iniciais
  AND r.classificacao = 'Efetiva'
  AND r2.classificacao = 'Adiada'
LIMIT 50;
```

**Análise esperada:**
- Se Dúvida #1 respondeu "Efetiva" → É regressão (v2 está errada, corrigir)
- Se Dúvida #1 respondeu "Adiada" → É correção (v1 estava errada, é melhoria)
- Se Dúvida #1 ainda não respondida → Documentar como regressão potencial

### Delta tipo B: Adiada (v1) → Efetiva (v2) — Melhoria?

```sql
-- Exemplo: UNA com sinal em 3 dias úteis (Dúvida #3)
SELECT 
    r.id_processo_audiencia,
    r.nr_processo,
    r.dta_audiencia,
    (SELECT dia FROM audiencias_subsequentes s WHERE s.id_processo_audiencia = r.id_processo_audiencia LIMIT 1) AS dt_proxima,
    (SELECT COUNT(*) FROM movimentos_diligencia m WHERE m.id_processo_audiencia = r.id_processo_audiencia) AS qtd_diligencias,
    r2.classificacao AS class_v2,
    r2.motivo_classificacao
FROM resultado_v1 r
JOIN resultado_v2 r2 USING (id_processo_audiencia)
WHERE r.id_tipo_audiencia = ANY(ARRAY[5,19,23,31,7,9]) -- UNAs
  AND r.classificacao = 'Adiada'
  AND r2.classificacao = 'Efetiva'
LIMIT 50;
```

**Análise esperada:**
- Verificar se `motivo` é "Regra 3a (diligência + Encerramento)" ou "Regra 3b (Julgamento)"
- Se lógica estiver correta → É melhoria (v2 está certa)
- Se lógica estiver errada → Bug (corrigir, reprocessar)

---

## ✅ FASE 3.6: Validação de Casos Críticos

Rodar manualmente para cada dúvida SETIC respondida:

### Dúvida #1: Inicial sem nova audiência

```sql
SELECT COUNT(*) AS qtd_adiada_agora
FROM resultado_v2 r2
JOIN resultado_v1 r1 USING (id_processo_audiencia)
WHERE r2.id_tipo_audiencia = ANY(ARRAY[3,16,22,29]) -- Iniciais
  AND (SELECT COUNT(*) FROM audiencias_subsequentes s 
       WHERE s.id_processo_audiencia = r2.id_processo_audiencia) = 0
  AND r2.classificacao = 'Adiada';
  
-- Esperado conforme resposta SETIC:
-- Se resposta = "Efetiva": esse COUNT deveria estar em Efetiva (BUG)
-- Se resposta = "Adiada": esse COUNT está correto (OK)
```

**Checklist:**
- [ ] Classificação alinhada com resposta SETIC
- [ ] Motivo documentado
- [ ] Amostra verificada manualmente (10–20 casos)

### Dúvida #3: Instrução sem diligência e sem Julgamento

```sql
SELECT COUNT(*) AS qtd_adiada_por_omissao
FROM resultado_v2 r2
WHERE r2.id_tipo_audiencia = ANY(ARRAY[6,12,24,27]) -- Instruções
  AND r2.motivo_classificacao LIKE '%omissão%' OR motivo_classificacao LIKE '%nenhuma opção%'
  AND r2.classificacao = 'Adiada';
```

**Checklist:**
- [ ] Resposta SETIC confirma "Adiada por padrão" ou há outra regra?
- [ ] Se outra regra: implementar e re-testar

### Dúvida #5: Sentença terminativa

```sql
SELECT COUNT(*) AS qtd_terminativa_detectada
FROM resultado_v2 r2
WHERE r2.motivo_classificacao LIKE '%sentença terminativa%'
  AND r2.classificacao = 'Efetiva';
  
-- Se resposta SETIC = "Sim, é prolação": OK
-- Se resposta SETIC = "Não": remover e reclassificar
```

**Checklist:**
- [ ] Resposta SETIC: sentença terminativa conta?
- [ ] Se SIM: ativar flag no código
- [ ] Se NÃO: comentar eventos 456/458/459/461/463/464/465/454/50126

### Dúvida #6: Perícia ativa (quando avaliar?)

```sql
SELECT COUNT(*) AS qtd_pericia_ativa_detectada
FROM resultado_v2 r2
WHERE r2.flg_pericias_ativas_na_janela = TRUE
  AND r2.classificacao = 'Efetiva';
```

**Checklist:**
- [ ] Resposta SETIC: perícia ativa é estado hoje ou fim da janela?
- [ ] Implementação atual usa CURRENT_DATE - 1 (comparar com resposta)

---

## 📈 FASE 3.7: Métricas Finais

```sql
-- Resumo comparativo
SELECT 
    'v1' AS versao,
    COUNT(*) AS total,
    SUM(CASE WHEN classificacao = 'Efetiva' THEN 1 ELSE 0 END) AS efetivas,
    ROUND(100.0 * SUM(CASE WHEN classificacao = 'Efetiva' THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_efetiva
FROM resultado_v1
UNION ALL
SELECT 
    'v2' AS versao,
    COUNT(*) AS total,
    SUM(CASE WHEN classificacao = 'Efetiva' THEN 1 ELSE 0 END) AS efetivas,
    ROUND(100.0 * SUM(CASE WHEN classificacao = 'Efetiva' THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_efetiva
FROM resultado_v2
ORDER BY versao;

-- Performance (v2 vs v1)
-- Executar ambas e comparar tempo de execução
EXPLAIN ANALYZE SELECT ... FROM audiencias_realizadas_v2_draft;
-- Esperado: +5–10% vs v1 (CTEs adicionais, calendário)
```

**Checklist:**
- [ ] % Efetiva dentro de range esperado (confirmar com SETIC)
- [ ] Performance aceitável (<2s para ~100k)
- [ ] Nenhuma query timed out

---

## 📝 FASE 3.8: Documentar Resultados

Criar arquivo: `docs/RESULTADO_TESTES_FASE_3.md`

```markdown
# Resultado de Testes — Fase 3

**Data de execução:** [data]
**Volume testado:** [count] audiências
**Período:** [data_inicio] a [data_fim]

## Resumo

| Métrica | v1 | v2 | Delta |
|---------|----|----|-------|
| Total | X | Y | ±Z% |
| Efetivas | X | Y | ±Z% |
| % Efetiva | X% | Y% | ±Z pp |
| Performance | X ms | Y ms | ±Z% |

## Mudanças Identificadas

### Regressões (Efetiva→Adiada): [N] casos
- [Listar e justificar cada uma]

### Melhorias (Adiada→Efetiva): [N] casos
- [Listar e justificar cada uma]

## Validação de Dúvidas SETIC

- [ ] Dúvida #1: Testado, resultado [confirmado/rejeitado]
- [ ] Dúvida #3: Testado, resultado [confirmado/rejeitado]
- [ ] Dúvida #5: Testado, resultado [confirmado/rejeitado]
- [ ] Dúvida #6: Testado, resultado [confirmado/rejeitado]

## Aprovação

- [ ] Testes OK, regressões documentadas e aprovadas
- [ ] Pronto para Fase 4 (Monitoramento)
- [ ] Pronto para Fase 5 (Produção)
```

**Checklist:**
- [ ] Arquivo criado e preenchido
- [ ] Compartilhado com SETIC e stakeholders
- [ ] Aprovação obtida

---

## 🚨 Troubleshooting Rápido

| Problema | Causa Provável | Solução |
|----------|----------------|---------|
| v2 retorna 20% menos registros | Filtro de data muito restritivo | Confirmar VAR_ULT_DT_AUDIENCIA |
| % Efetiva muito diferente | Implementação de regra incorreta | Re-ler PLANO_TESTES_FASE_3.md seção 3 |
| Query v2 timed out | Calendário fazendo full scan | Adicionar índice em tb_calendario_eventos |
| Deltas anormalmente altos (>20%) | Resposta SETIC mudou interpretação | Sincronizar com SETIC, revisar implementação |

---

## ✔️ Critério de Sucesso (Go/No-Go)

**GO para Fase 4** quando:
- [x] Ambas as queries rodam sem erro
- [x] v2 retorna 98–102% do volume de v1
- [x] % Efetiva está dentro de range esperado (±5%)
- [x] Regressões identificadas e documentadas
- [x] Cada caso crítico testado com ≥1 caso real
- [x] Performance aceitável
- [x] SETIC aprova resultado

**NO-GO para Fase 4** se:
- [ ] Implementação não alinha com resposta SETIC
- [ ] Regressão inexplicada > 10%
- [ ] Query falha em >0,1% dos dados
- [ ] Performance degrada significativamente (>2x)

---

**Mantainer:** eric.lmello2024@gmail.com  
**Último update:** 2026-09-25  
**Próxima revisão:** Quando Fase 3 executada
