# Guia Operacional — Classificação de Audiências v2 (Fase 5)

**Versão:** 2.0  
**Status:** Planejado para produção (após Fase 3 e 4)  
**Data:** 2026-09-25  
**Responsável:** Eric Lmello (eric.lmello2024@gmail.com)

---

## Resumo Executivo

Este guia cobre a operação, monitoramento e manutenção do sistema de classificação de audiências em produção, incluindo:

- Deploy seguro com rollback
- Execução agendada (carga, reprocessamento)
- Monitoramento contínuo (KPIs, alertas)
- Troubleshooting e runbooks
- Escalação e suporte

**Pré-requisitos para produção:**
- ✅ Fase 3 aprovada (testes OK, sem regressões bloqueantes)
- ✅ Fase 4a–4c operacional (tabelas, views, procedures)
- ✅ Decisão SETIC #4 sobre watermark (para Fase 4d)
- ✅ Aprovação de segurança e arquitetura

---

## 1. Deploy Inicial em Produção

### 1.1 Pré-deploy Checklist

Antes de executar qualquer mudança em produção:

- [ ] Backup completo de banco (full backup + WAL)
- [ ] Plano de rollback documentado e testado
- [ ] Comunicado para stakeholders (data/hora do deploy)
- [ ] Janela de manutenção agendada (fora de horário de pico)
- [ ] Contatos de escalação confirmados
- [ ] Testes finais em QA aprovados

### 1.2 Passos de Deploy

```bash
# PASSO 1: Criar tabelas de monitoramento (Fase 4a)
psql -U usuario_producao -h host_producao -f sql/tabelas_monitoramento_fase4.sql

# PASSO 2: Criar procedures (Fase 4b)
psql -U usuario_producao -h host_producao -f sql/procedimentos_fase4b.sql

# PASSO 3: Integrar query v2 (Fase 2 finalizada)
# → Substituir placeholder em procedimentos_fase4b.sql com SELECT real
# → SQL: criar schema pai_2_0 se não existir
psql -U usuario_producao -h host_producao -c "CREATE SCHEMA IF NOT EXISTS pai_2_0;"

# PASSO 4: Teste funcional
psql -U usuario_producao -h host_producao -c \
  "CALL pai_2_0.sp_executar_classificacao('2.0', 'TESTE', 'admin_deploy');"

# Verificar resultados
psql -U usuario_producao -h host_producao -c \
  "SELECT COUNT(*), COUNT(*) FILTER (WHERE classificacao='Efetiva') FROM pai_2_0.fato_audiencia_classificada;"

# PASSO 5: Se teste passou → Agendar carga periódica (ver seção 3)
```

### 1.3 Rollback de Emergência

Se problema crítico for detectado:

```bash
# OPÇÃO A: Restaurar último backup completo
pg_restore -U usuario_producao -h host_producao -d pai < backup_pre_deploy.sql

# OPÇÃO B: Remover tabelas/procedures (se problema é apenas Fase 4)
psql -U usuario_producao -h host_producao -c \
  "DROP TABLE IF EXISTS pai_2_0.fato_audiencia_classificada, 
                        pai_2_0.trilha_execucao,
                        pai_2_0.metrica_integridade CASCADE;"

# OPÇÃO C: Desativar cron/job de produção e reabilitar query v1 (se necessário)
# → Ver detalhes de Job Scheduler (seção 3.3)
```

---

## 2. Integração com Ambiente de Produção

### 2.1 Requisitos de Ambiente

| Recurso | Especificação | Justificativa |
|---------|---------------|---------------|
| Disco | +500GB | 2M+ registros em fato_audiencia (cada ~300 bytes) |
| RAM | 16GB mínimo | Índices de trabalho + query v2 processamento |
| CPU | 4+ cores | Reprocessamento de 45 dias em paralelo |
| IOPS | 5000+ | Escritas UPSERT contínuas durante carga |
| Conexões DB | 5+ reservadas | Cron + manual + alertas |
| Tempo de execução | <60 min | Query v2 (expectativa: 30-40 min com 100k) |

### 2.2 Credenciais e Permissões

```sql
-- Criar usuário dedicado para Fase 5 (mínimo privilégio)
CREATE USER usuario_audiencias WITH PASSWORD 'senha_segura';

GRANT USAGE ON SCHEMA pai_2_0 TO usuario_audiencias;
GRANT SELECT, INSERT, UPDATE ON pai_2_0.fato_audiencia_classificada TO usuario_audiencias;
GRANT SELECT, INSERT ON pai_2_0.trilha_execucao TO usuario_audiencias;
GRANT SELECT, INSERT, UPDATE ON pai_2_0.metrica_integridade TO usuario_audiencias;
GRANT EXECUTE ON ALL PROCEDURES IN SCHEMA pai_2_0 TO usuario_audiencias;

-- Readonly para análise (dashboards)
CREATE USER usuario_analise WITH PASSWORD 'senha_analise';
GRANT USAGE ON SCHEMA pai_2_0 TO usuario_analise;
GRANT SELECT ON ALL TABLES IN SCHEMA pai_2_0 TO usuario_analise;
GRANT SELECT ON ALL VIEWS IN SCHEMA pai_2_0 TO usuario_analise;
```

### 2.3 Variáveis de Ambiente

```bash
# .env ou equivalent (nunca em repo)
PAI_DB_HOST=producao.example.com
PAI_DB_PORT=5432
PAI_DB_USER=usuario_audiencias
PAI_DB_PASSWORD=senha_segura  # Use secrets manager
PAI_DB_NAME=pai
PAI_SCHEMA=pai_2_0
PAI_LOG_DIR=/var/log/audiencias/
PAI_ALERT_EMAIL=operacoes@example.com
PAI_ALERT_SLACK=#audiencias-ops
```

---

## 3. Execução Agendada e Carga

### 3.1 Cronograma Padrão

| Execução | Frequência | Tipo | Janela | Propósito |
|----------|-----------|------|--------|-----------|
| Carga incremental | Diária às 23:00 UTC | INICIAL | 60 min | Processar audiências do dia |
| Reprocessamento | Semana 1 e 3 | REPROCESSAMENTO | 120 min | Corrigir lacunas (rolling window) |
| Auditoria v1↔v2 | Mensal | AUDITORIA | 180 min | Detectar perda de dados |
| Backup completo | Diária 02:00 UTC | — | 90 min | Disaster recovery |

### 3.2 Job Scheduler Setup

#### Opção A: PostgreSQL pg_cron

```sql
-- Extensão necessária
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Agendamento
SELECT cron.schedule(
    'audiencias_carga_diaria',
    '0 23 * * *', -- 23:00 UTC diariamente
    'CALL pai_2_0.sp_executar_classificacao(''2.0'', ''INICIAL'', ''pg_cron'')'
);

SELECT cron.schedule(
    'audiencias_reprocessamento_semanal',
    '0 3 * * 1', -- 03:00 UTC segunda-feira
    'CALL pai_2_0.sp_executar_classificacao(''2.0'', ''REPROCESSAMENTO'', ''pg_cron'')'
);

SELECT cron.schedule(
    'audiencias_auditoria_mensal',
    '0 1 1 * *', -- 01:00 UTC dia 1 de cada mês
    'CALL pai_2_0.sp_validar_integridade_dados(''2.0'')'
);
```

#### Opção B: Airflow (recomendado para produção)

```python
from airflow import DAG
from airflow.operators.postgres_operator import PostgresOperator
from datetime import datetime, timedelta

default_args = {
    'owner': 'audiencias',
    'retries': 2,
    'retry_delay': timedelta(minutes=5),
}

dag = DAG(
    'audiencias_classificacao_v2',
    default_args=default_args,
    schedule_interval='0 23 * * *',  # 23:00 UTC diariamente
    catchup=False,
    tags=['audiencias', 'critica'],
)

carga_diaria = PostgresOperator(
    task_id='carga_diaria',
    postgres_conn_id='pai_producao',
    sql="CALL pai_2_0.sp_executar_classificacao('2.0', 'INICIAL', 'airflow');",
    dag=dag,
)

validacao = PostgresOperator(
    task_id='validacao_integridade',
    postgres_conn_id='pai_producao',
    sql="CALL pai_2_0.sp_validar_integridade_dados('2.0');",
    trigger_rule='all_done',  # Rodar mesmo se carga falhar
    dag=dag,
)

carga_diaria >> validacao
```

### 3.3 Monitoramento de Execução

Após cada execução agendada, verificar:

```sql
-- Ver últimas 10 execuções
SELECT
    dt_execucao,
    origem,
    qtd_audiencias_processadas,
    qtd_classificadas_efetiva,
    ROUND(100.0 * qtd_classificadas_efetiva / NULLIF(qtd_audiencias_processadas, 0), 2) AS pct_efetiva,
    duracao_ms,
    status
FROM pai_2_0.trilha_execucao
ORDER BY dt_execucao DESC
LIMIT 10;

-- Ver alertas de regressão
SELECT
    dt_execucao_atual,
    pct_efetiva_atual,
    pct_efetiva_anterior,
    delta_pct,
    status_alerta
FROM pai_2_0.v_regressoes_potenciais
WHERE status_alerta != 'OK';

-- Ver distribuição por tipo de audiência
SELECT
    categoria_regra,
    variante,
    qtd_audiencias,
    qtd_efetiva,
    pct_efetiva
FROM pai_2_0.v_distribuicao_tipos_audiencia
ORDER BY qtd_audiencias DESC;
```

---

## 4. Monitoramento Contínuo

### 4.1 KPIs Críticos

| Métrica | Alvo | Amarelo | Vermelho | Frequência |
|---------|------|--------|----------|-----------|
| % Efetiva | 85-95% | <83% ou >97% | <80% ou >98% | Diária |
| Regressão vs. anterior | 0% | >2% | >5% | Diária |
| Duração execução | <40min | >50min | >60min | Diária |
| Acurácia auditoria v1↔v2 | <0.5% delta | >0.5% | >1% | Mensal |
| Perda de dados detectada | 0 eventos | 1 evento | 2+ eventos | Contínuo |

### 4.2 Dashboard

Implementar dashboard (ex.: Grafana, Metabase) com:

- Série temporal de % Efetiva (últimos 90 dias)
- Distribuição de tipos (gráfico de pizza ou sunburst)
- Status de últimas 10 execuções (tabela com cor)
- Alertas acionados (timeline)
- Comparação v1 vs v2 (scatter plot de volume)

**Queries para dashboard:**

```sql
-- % Efetiva ao longo do tempo
SELECT
    DATE(dt_execucao) AS data,
    ROUND(100.0 * AVG(qtd_classificadas_efetiva / NULLIF(qtd_audiencias_processadas, 0)), 2) AS pct_efetiva_media
FROM pai_2_0.trilha_execucao
WHERE status = 'SUCESSO'
GROUP BY DATE(dt_execucao)
ORDER BY data DESC
LIMIT 90;

-- Distribuição atual
SELECT
    classificacao,
    COUNT(*) AS qtd,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct
FROM pai_2_0.fato_audiencia_classificada
WHERE versao_regra = '2.0'
GROUP BY classificacao;
```

### 4.3 Alertas e Escalação

| Alerta | Condição | Ação | Escalação |
|--------|----------|------|-----------|
| Regressão > 5% | `pct_efetiva - pct_anterior < -5` | Pausar alertas públicos | PM + Engenharia |
| Execução falhou | `trilha_execucao.status = 'FALHA'` | Notificar ops | Ops + Engenharia |
| Perda de dados | `v1_qtd - v2_qtd > 0.5%` | CRÍTICO: escalação imediata | Gerência + SETIC |
| Duração > 60min | `duracao_ms > 3600000` | Investigar bottleneck | DBA + Engenharia |
| Sem execução 24h | Nenhuma linha em trilha_execucao | Verificar scheduler | Ops + Engenharia |

**Implementação com Grafana alerts:**

```yaml
alert:
  name: "Regressão de % Efetiva > 5%"
  condition:
    - target: v_regressoes_potenciais
      expr: "delta_pct < -5"
  annotations:
    description: "Efetiva caiu {{ $value }}% desde última execução"
    runbook: "https://wiki/troubleshooting#regressao-efetiva"
  notify:
    - slack: "#audiencias-ops"
    - email: "operacoes@example.com"
    - pagerduty: "audiencias-oncall"
```

---

## 5. Troubleshooting e Runbooks

### 5.1 Problema: Regressão > 5%

**Sintomas:** % Efetiva cai abruptamente (ex.: 90% → 83%)

**Investigação:**

```sql
-- 1. Ver últimas execuções
SELECT * FROM pai_2_0.v_regressoes_potenciais;

-- 2. Comparar sinais acionados
SELECT
    flg_incompetencia,
    flg_inicial_com_subsequente,
    flg_mesma_categoria_redesignada,
    COUNT(*) AS qtd
FROM pai_2_0.fato_audiencia_classificada
WHERE versao_regra = '2.0'
  AND data_calculo >= NOW() - INTERVAL '1 day'
GROUP BY 1,2,3
ORDER BY qtd DESC;

-- 3. Comparar v1 vs v2 (primeira vez)
CALL pai_2_0.sp_validar_integridade_dados('2.0');

-- 4. Ver delta por tipo
SELECT
    m.categoria_regra,
    COUNT(*) AS qtd,
    SUM(CASE WHEN f.classificacao = 'Efetiva' THEN 1 ELSE 0 END) AS efetiva,
    ROUND(100.0 * SUM(CASE WHEN f.classificacao = 'Efetiva' THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct
FROM pai_2_0.fato_audiencia_classificada f
LEFT JOIN pai_2_0.mapeamento_tipos_audiencia m ON TRUE
WHERE f.versao_regra = '2.0'
  AND f.data_calculo >= NOW() - INTERVAL '1 day'
GROUP BY m.categoria_regra
ORDER BY qtd DESC;
```

**Causas comuns:**

1. **SETIC respondeu dúvida #3 ou #5** → Query v2 mudou (esperado)
   - Ação: Validar mudança, atualizar documentação, subir versão (v2.1)

2. **Bug em query v2** → Regra aplicada incorretamente
   - Ação: Ver logs de query, criar issue, fazer reprocessamento com v2.0 após fix

3. **Dados ruins em entrada** → Registros inconsistentes em tb_processo_audiencia
   - Ação: Validar dados PJe, correção com DBA

4. **Watemark perdendo dados** → Audiências não reprocessadas
   - Ação: Ver seção 5.3, ativar rolling window (Opção A)

**Resolução:**

```bash
# A. Se revert necessário (usar versão anterior)
# Criar nova versão '2.0-rollback' apontando para query v1
CALL pai_2_0.sp_executar_classificacao('2.0-rollback', 'REVERT', 'admin');

# B. Se fix em query v2
# Atualizar procedimentos_fase4b.sql com SELECT v2 correto
CALL pai_2_0.sp_executar_classificacao('2.1', 'CORRECAO', 'admin');

# C. Se dados ruins
# Limpar e reprocessar 90 dias
DELETE FROM pai_2_0.fato_audiencia_classificada WHERE data_calculo < NOW() - INTERVAL '90 days';
CALL pai_2_0.sp_executar_classificacao('2.0', 'REPROCESSAMENTO', 'admin');
```

### 5.2 Problema: Execução Falhou

**Sintomas:** `trilha_execucao.status = 'FALHA'`

**Investigação:**

```sql
SELECT * FROM pai_2_0.trilha_execucao WHERE status LIKE 'FALHA%' ORDER BY dt_execucao DESC LIMIT 1;

-- Ver erro em log de procedure
-- PostgreSQL: SELECT pg_read_file('pg_log/...') -- se logging está ativo
```

**Causas comuns e soluções:**

| Erro | Causa | Ação |
|------|-------|------|
| "disk space" | Disco cheio | Limpar logs antigos; adicionar disco |
| "out of memory" | Query v2 muito grande | Otimizar query; aumentar shared_buffers |
| "connection timeout" | DB não respondendo | Reiniciar DB; verificar bloqueios |
| "permission denied" | Usuário sem acesso | Verificar GRANT; usar usuário_audiencias |
| "constraint violation" | PK duplicada em UPSERT | Query v2 gerando ids duplicados; investigar lógica |

**Retry manual:**

```bash
# Reexecutar última carga
psql -U usuario_producao -h host_producao -c \
  "CALL pai_2_0.sp_executar_classificacao('2.0', 'INICIAL', 'retry_manual');"

# Se ainda falhar → Backup + escalação
```

### 5.3 Problema: Possível Perda de Dados (Watermark)

**Sintomas:** `v_regressoes_potenciais` mostra delta > 0.5%, mas nenhuma mudança de regra

**Investigação:**

```sql
-- 1. Comparar volumes v1 vs v2
SELECT
    (SELECT COUNT(*) FROM pai_2_0.audiencias WHERE status <> 'Programada') AS v1_qtd,
    (SELECT COUNT(*) FROM pai_2_0.fato_audiencia_classificada WHERE versao_regra = '2.0') AS v2_qtd,
    ROUND(100.0 * ABS(
        (SELECT COUNT(*) FROM pai_2_0.audiencias WHERE status <> 'Programada') -
        (SELECT COUNT(*) FROM pai_2_0.fato_audiencia_classificada WHERE versao_regra = '2.0')
    ) / NULLIF((SELECT COUNT(*) FROM pai_2_0.audiencias WHERE status <> 'Programada'), 0), 2) AS pct_delta;

-- 2. Ver watermarks históricos
SELECT
    watermark_entrada_dt_audiencia,
    watermark_saida_dt_audiencia,
    qtd_audiencias_processadas,
    (watermark_saida_dt_audiencia - watermark_entrada_dt_audiencia) AS dias_processados
FROM pai_2_0.trilha_execucao
ORDER BY dt_execucao DESC
LIMIT 20;

-- 3. Se gap > 45 dias entre watermarks → ALERTA perda de dados
```

**Resolução:**

Se perda confirmada:

```bash
# CRÍTICO: Implementar Opção A (Rolling Window) imediatamente
# 1. Modificar sp_executar_classificacao (linha ~51):
#    OLD: SELECT MAX(dt_audiencia) INTO v_watermark_entrada
#    NEW: SELECT MAX(dt_audiencia) - INTERVAL '45 days' INTO v_watermark_entrada

# 2. Limpar fato_audiencia_classificada (perder dados problemáticos)
CALL pai_2_0.sp_limpar_fato_audiencia_classificada();

# 3. Reprocessar tudo com rolling window (45 dias + histórico)
psql -U usuario_producao -h host_producao -f sql/procedimentos_fase4b_updated.sql
CALL pai_2_0.sp_executar_classificacao('2.0', 'REPROCESSAMENTO_COMPLETO', 'admin');

# 4. Validar resultado
CALL pai_2_0.sp_validar_integridade_dados('2.0');

# 5. Notificar stakeholders
```

---

## 6. Manutenção Periódica

### 6.1 Limpeza de Dados Históricos

```sql
-- Manter últimos 6 meses de trilha_execucao (rest arquivar)
DELETE FROM pai_2_0.trilha_execucao
WHERE dt_execucao < NOW() - INTERVAL '6 months'
  AND status = 'SUCESSO'; -- Manter FALHAs mais tempo para debug

-- Aspiração de fato_audiencia_classificada (manter apenas última versão por id_processo)
-- Só executar se reprocessamento confirmar estabilidade
-- DELETE FROM pai_2_0.fato_audiencia_classificada
-- WHERE versao_regra != '2.0'
--   AND nro_reprocessamento = 1; -- Primeira execução de cada versão
```

### 6.2 Otimização de Índices

```sql
-- Reindex mensal (se performance degradar)
REINDEX TABLE pai_2_0.fato_audiencia_classificada;

-- Analyze estatísticas
ANALYZE pai_2_0.fato_audiencia_classificada;
ANALYZE pai_2_0.trilha_execucao;

-- Vacuum full (se muita fragmentação)
VACUUM FULL ANALYZE pai_2_0.fato_audiencia_classificada;
```

### 6.3 Upgrade de Query

Quando SETIC responde dúvida (#1, #3, #5), ou necessário fix:

```bash
# 1. Criar nova versão em query v2
# 2. Testar em QA com dados de teste
# 3. Criar nova entrada em mapeamento_tipos_audiencia se novo tipo
# 4. Criar branch git: feature/audiencias-v2.1-duvida-xyz
# 5. Deploy com versão v2.1:
CALL pai_2_0.sp_executar_classificacao('2.1', 'INICIAL', 'admin_upgrade');

# 6. Monitorar regressão por 7 dias
# 7. Se OK → manter v2.1; se problema → revert para v2.0
```

---

## 7. Escalação e Contatos

### Matriz de Escalação

```
┌─ NÍVEL 1: Operações (24/7)
│  - Monitorar alertas
│  - Executor runbooks
│  - Contato: operacoes@example.com | #ops-slack
│
├─ NÍVEL 2: Engenharia de Dados (BHO)
│  - Troubleshoot query v2
│  - Otimizar performance
│  - Contato: engenharia-dados@example.com | Eric Lmello
│
├─ NÍVEL 3: DBA / Arquitetura
│  - Problemas de storage/replicação
│  - Decisões de design
│  - Contato: dba@example.com
│
└─ NÍVEL 4: Negócio (SETIC) / Escalação Executiva
   - Dúvidas de critério
   - Decisões de regressão > 5%
   - Contato: gerencia-setic@example.com
```

### Runbook de Escalação

| Cenário | L1 Ação | L2 Envolvê-lo se | L3 Envolvê-lo se | L4 Envolvê-lo se |
|---------|---------|------------------|------------------|------------------|
| Regressão > 2% | Alertar | >2% | >5% | >10% ou métrica reportada |
| Execução falhou | Retry 3x | 3ª falha consecutiva | Falha > 6h | Falha > 24h |
| Perda de dados | Alerta crítica | Confirmado | IMEDIATAMENTE | IMEDIATAMENTE |
| Performance degradou | Monitorar | Duração > 60min | >90min ou SLA break | SLA crítico break |

---

## 8. Disaster Recovery

### 8.1 Backup & Restore

```bash
# Backup automático (cron)
0 2 * * * pg_dump -U usuario_producao pai > /backups/pai_$(date +\%Y\%m\%d).sql.gz

# Restore de backup
pg_restore -U usuario_producao -d pai < /backups/pai_20261001.sql

# Point-in-time recovery (se WAL está ativo)
# → Contatar DBA para restore em timestamp específico
```

### 8.2 Failover para Standby

```bash
# PostgreSQL replicação
# 1. Verificar status standby
psql -U usuario_producao -h standby -c "SELECT pg_is_in_recovery();"

# 2. Promover standby (se primary falhou)
psql -U usuario_producao -h standby -c "SELECT pg_promote();"

# 3. Executar procedimentos de novo
CALL pai_2_0.sp_executar_classificacao('2.0', 'INICIAL', 'failover');
```

---

## 9. Referência Rápida

### Comandos Mais Usados

```sql
-- Ver última execução
SELECT * FROM pai_2_0.v_ultimas_execucoes LIMIT 5;

-- Ver alertas ativos
SELECT * FROM pai_2_0.v_regressoes_potenciais WHERE status_alerta != 'OK';

-- Executar carga manual
CALL pai_2_0.sp_executar_classificacao('2.0', 'INICIAL', 'manual_admin');

-- Reprocessar últimos 7 dias
DELETE FROM pai_2_0.fato_audiencia_classificada
WHERE data_calculo >= NOW() - INTERVAL '7 days';
CALL pai_2_0.sp_executar_classificacao('2.0', 'REPROCESSAMENTO', 'admin');

-- Ver distribuição por tipo
SELECT * FROM pai_2_0.v_distribuicao_tipos_audiencia ORDER BY qtd_audiencias DESC;

-- Limpar tudo (dev/qa only!)
CALL pai_2_0.sp_limpar_fato_audiencia_classificada();
```

### Logs e Histórico

```bash
# Ver logs PostgreSQL (se log_statement='all')
tail -f /var/log/postgresql/postgresql.log | grep "sp_executar_classificacao"

# Ver historicamente % Efetiva
# → Query dashboard, export para CSV, análise trend
```

---

## 10. Contato e Suporte

**Desenvolvedor (code/arquitetura):**  
Eric Lmello  
Email: eric.lmello2024@gmail.com  
GitHub: ericlmello  

**Operações (alertas/monitoring):**  
Email: operacoes@example.com  
Slack: #audiencias-ops  
PagerDuty: audiencias-oncall  

**Negócio (decisões SETIC):**  
SETIC / Coordenação de Audiências  
Email: gerencia-setic@example.com  
Ticket: [sistema de chamados]  

---

**Versão:** 2.0 | **Última atualização:** 2026-09-25 | **Próxima revisão:** 2026-10-26 (pós-deploy)

