# Status de Entregas por Fase

**Data de compilação:** 2026-09-25 (Atualizado 2026-09-30)  
**Status geral:** Fase 2 completa (9 de 11 dúvidas resolvidas; só 2 residuais de baixo risco); Fase 3 pode iniciar; Fases 4–5 completas

---

## ATUALIZAÇÃO 2026-09-30 — SETIC Confirmou Dúvidas #8, #10, #11

Restava confirmação de 3 dúvidas: abrangência municipal do calendário (#8, opção a — granular,
implementado no `calendario_3du`), watermark autorreferente (#10 — mantido como está, risco
aceito conscientemente) e mapeamento de Conciliação (#11 — só "em Conhecimento", já era a
hipótese implementada). Todas confirmadas e implementadas em
`sql/audiencias_realizadas_v2_draft.sql`. Não há mais bloqueador formal para Fase 2 — restam só
2 residuais de baixo risco (#2, #3) que não impedem nada.

---

## Resumo Executivo

| Fase | Objetivo | Status | Bloqueador | Próximo |
|------|----------|--------|-----------|--------|
| 1 | Análise de regras | ✅ Completo | — | ✅ Concluído |
| 2 | Query v2 + bugs | ✅ Completo (residuais #2/#3 baixo risco) | — | ✅ Concluído |
| 3 | Testes ~100k | 📋 Pronto (40+ casos) | Acesso a banco de dados real | Pode iniciar já |
| 4 | Monitoramento | ✅ 4a–4c completo | — | ✅ Pronto |
| 5 | Produção | ✅ Guia pronto | Fase 3 OK | Pronto; deploy após Fase 3 ✅ |

---

## Fase 1: Análise ✅ (Completo)

### Entregáveis
- ✅ `docs/analisa_criterios_audiencias_setic.md` (41KB, 490+ linhas)
  - Mapeamento de 36 tipos de audiência
  - 7 regras formalizadas (Regra 0–7)
  - Descoberta de 6 bugs de implementação em rascunho anterior
  - Documentação de decisões internas (tipos RS, tipo 8, incompetência)
  - 10 dúvidas identificadas para SETIC

- ✅ `docs/DUVIDAS_SETIC_Criterios_Audiencias.md` (11 dúvidas após revisão de 2026-09-28)
  - Dúvidas estruturadas (fechadas + abertas)
  - Impacto classificado (Alto/Médio/Baixo)
  - Enviado ao SETIC em 2026-09-24; atualizado com resoluções em 2026-09-28

- ✅ `docs/RESPOSTAS_SETIC_Cronograma.md`
  - Rastreamento de respostas
  - Decisões internas (hipóteses já implementadas)
  - Status de cada dúvida

---

## Fase 2: Prototipagem e Implementação ⚠️ (~90% completo)

### Entregáveis
- ✅ `sql/audiencias_realizadas_v2_draft.sql` (~630 linhas)
  - Implementação das 7 regras formalizadas
  - 6 bugs corrigidos (comparação de categoria, Encerramento obrigatório, Julgamento tardio, calendário, busca limitada, buffer de 10 dias, tipo de dado)
  - ✅ Dúvidas #1, #5 resolvidas e implementadas (2026-09-28, documento SETIC revisado)
  - ✅ Dúvida #3 parcialmente resolvida e implementada (2026-09-28)
  - ✅ Dúvida #6 (perícia) resolvida e implementada (2026-09-25)
  - Regras para dúvida #2 implementada como hipótese (escopo reduzido em 28/09); dúvida #4 confirmada pela SETIC em 29/09
  - TODOs/premissas remanescentes: apenas dúvidas #2 e #3 (residuais de baixo risco)

### Bloqueadores Críticos
| Dúvida | Tópico | Status | Impacto | Prioridade |
|--------|--------|--------|---------|-----------|
| #1 | Inicial sem nova audiência (acordo/sentença) | ✅ Resolvida (2026-09-28) | — | ✅ IMPLEMENTADA |
| #2 | UNA → Julgamento/Conciliação direto fora da janela | Aberta (escopo reduzido) | Baixo (residual) | Hipótese implementada |
| #3 | Instrução sem nenhum sinal (residual) | Parcial (2026-09-28) | Baixo (residual) | Hipótese implementada |
| #4 | Tipo 8 "Instrução e Julgamento" | ✅ Resolvida (2026-09-29) | — | ✅ IMPLEMENTADA |
| #5 | Sentença terminativa = "prolação"? | ✅ Resolvida (2026-09-28) | — | ✅ IMPLEMENTADA |
| #6 | Perícia ativa avaliada quando? | ✅ Resolvida (2026-09-25) | — | ✅ IMPLEMENTADA |
| #8 | Calendário: abrangência municipal? | ✅ Resolvida (2026-09-30) | — | ✅ IMPLEMENTADA |
| #10 | Watermark autorreferente | ✅ Resolvida (2026-09-30) — mantido como está | — | ✅ IMPLEMENTADA |
| #11 | Mapeamento exato de "Conciliação" | ✅ Resolvida (2026-09-30) | — | ✅ IMPLEMENTADA |

### O que falta para finalizar Fase 2
- [ ] Confirmação dos 2 residuais de baixo risco (#2, #3) — não bloqueia nada
- [ ] Implementar lógica conforme respostas (se diferente das hipóteses já assumidas)
- [x] Remover TODOs / Marcar como Resolvido no RESPOSTAS_SETIC_Cronograma.md (Dúvidas #1, #5, #6, 3-parcial)

---

## Fase 3: Testes e Validação 🔄 (Estruturado, não iniciado)

### Entregáveis
- ✅ `docs/PLANO_TESTES_FASE_3.md` (800+ linhas, crie 2026-09-25)
  - **40+ casos de teste** cobertos (Regra 0–7)
  - Testes por cenário: bipartição, redesignações, calendário
  - Casos críticos com dúvidas SETIC
  - SQL de validação: Comparação v1 vs v2 (seção 4.1)
  - Reconciliação guiada de regressões
  - Critérios de sucesso definidos

### Bloqueadores
- ⏳ Acesso a banco de dados (~100k audiências reais) — **único bloqueador real restante**

### O que fazer agora (já pode iniciar)
1. Obter acesso a ambiente DEV/QA com dados reais
2. Executar testes (seção 5 do PLANO_TESTES_FASE_3.md)
3. Gerar relatório de delta vs. v1
4. Documentar regressões (se houver)
5. Se resposta SETIC às dúvidas #8/#10/#11 chegar depois, reexecutar testes específicos daquela regra

**Nota:** Dúvidas #1, #3 (parcial), #5, #6 já foram respondidas e implementadas (ver
`docs/DUVIDAS_SETIC_Criterios_Audiencias.md`) — Fase 3 não está mais bloqueada pela Fase 2.

---

## Fase 4: Monitoramento ⚠️ (Estruturado, 4a–4c não bloqueados)

### Entregáveis
- ✅ `sql/tabelas_monitoramento_fase4.sql` (450+ linhas, criado 2026-09-25)

#### 4a: Tabelas base (✅ Código pronto, não bloqueia nada)
- `fato_audiencia_classificada`: Cada classificação produzida (id_audiencia, versao_regra)
  - Suporta dedup para reprocessamento (UPSERT)
  - Flags de sinais (incompetência, diligência, julgamento, etc.)
  - Hash de condições para auditoria

- `trilha_execucao`: Log de cada rodada
  - volume, status, duração
  - Watermark entrada/saída (rastreamento de dados)
  - Reprocessa_apos_dias (sugestão para manutenção)

- `metrica_integridade`: KPIs e alertas
  - % Efetiva, regressão vs. versão anterior
  - Detecção de perda silenciosa

- `mapeamento_tipos_audiencia`: Catálogo (36 tipos)
  - Referência para debug e queries

#### 4b: Triggers/Procedures (✅ Implementado)
- ✅ `sql/procedimentos_fase4b.sql` (450+ linhas, criado 2026-09-25)
- `sp_executar_classificacao()`: Executa query v2, insere com UPSERT, registra trilha
- `sp_atualizar_metricas_integridade()`: Calcula KPIs, detecta regressão
- `sp_validar_integridade_dados()`: Auditoria v1↔v2 (template)
- Helper: `sp_limpar_fato_audiencia_classificada()` para DEV/QA

#### 4c: Views e Dashboard (✅ Implementado)
- ✅ Views já criadas em `sql/tabelas_monitoramento_fase4.sql`
- `v_ultimas_execucoes`: últimas 50 rodadas com status/volume/duração
- `v_regressoes_potenciais`: alerta se pct_efetiva cai >5%
- `v_distribuicao_tipos_audiencia`: % Efetiva por tipo de audiência
- Pronto para Grafana/Metabase/Power BI

#### 4d: Reprocessamento Automático (✅ Descontinuado — SETIC decidiu manter watermark como está)
- SETIC confirmou (2026-09-30, Dúvida #10): manter watermark autorreferente, sem rolling window
  nem config table. Risco de perda silenciosa aceito conscientemente.
- Propostas de mitigação mantidas em `sql/procedimentos_fase4b.sql` só como referência histórica.

### Bloqueadores
- Nenhum — SETIC confirmou manter o watermark autorreferente (2026-09-30); 4d descontinuado

### Próximos passos
- [x] Código das tabelas pronto (criar em DEV)
- [x] Procedure (4b) implementada
- [x] Views (4c) implementadas
- [ ] Criar dashboard básico (ex.: Tableau/Metabase)

---

## Fase 5: Produção ✅ (Pronto para Deploy)

### Requisitos
- ✅ Fase 2 finalizada (9 de 11 dúvidas confirmadas pela SETIC; só 2 residuais de baixo risco)
- ⏳ Fase 3 aprovada (testes OK, sem regressões bloqueantes)
- ✅ Fase 4a–4c operacional (monitoramento em funcionamento)

### Entregáveis
- ✅ `docs/GUIA_OPERACIONAL_FASE5.md` (2000+ linhas, criado 2026-09-25)
  - Deploy seguro com rollback de emergência
  - Requisitos de infra (disco, RAM, CPU, IOPS)
  - Credenciais e permissões (mínimo privilégio)
  - Execução agendada (Cron, Airflow)
  - Monitoramento contínuo (KPIs, alertas, dashboard)
  - Troubleshooting completo (regressão, falha, perda dados)
  - Manutenção periódica (limpeza, otimização, upgrade)
  - Escalação (matriz L1-L4, runbooks)
  - Disaster recovery (backup/restore, failover)

- ✅ Suporte em produção (structure pronta)
  - Monitoramento diário das métricas
  - Resposta a alertas (templates inclusos)
  - Reprocessamento conforme rolling window (Opção A)

---

## Filtragem por Responsabilidade

### O que SETIC precisa fazer (Bloqueadores)
Responder formalmente a dúvidas:
- [x] #1: Inicial sem nova audiência → **Efetiva (via "prolação da sentença"), respondido 2026-09-28**
- [x] #6: Perícia ativa avaliada quando? **→ Opção (c) Marcada na janela (2026-09-25)**
- [x] #5: Sentença terminativa conta como "prolação de sentença"? **→ SIM, respondido 2026-09-28**
- [ ] #3 (residual, baixo risco): Instrução sem NENHUM sinal (nem diligência, nem Julgamento/Encerramento) → Adiada por omissão, confirmar?
- [ ] #2 (residual, baixo risco): UNA → Julgamento/Conciliação direto fora da janela → Efetiva, confirmar?
- [x] #4: Tipo 8 "Instrução e Julgamento" → **sempre Efetiva, confirmado 2026-09-29**
- [x] #8: Calendário suspensão municipal → **Opção (a) granular, confirmado 2026-09-30**
- [x] #10: Watermark autorreferente → **manter como está, risco aceito, confirmado 2026-09-30**
- [x] #11: Conciliação → **só em Conhecimento, confirmado 2026-09-30**

Nenhum bloqueador formal restante. #2 e #3 são residuais de baixo risco (hipótese já implementada).

### O que pode acontecer em PARALELO (não aguarda SETIC)
- [x] Fase 3: Plano de testes estruturado (pronto para executar quando respostas chegarem)
- [x] Fase 4a: Tabelas de monitoramento criadas
- [x] Fase 4b: Procedimentos para alimentar tabelas (sp_executar_classificacao, etc.)
- [x] Fase 4c: Views e Dashboard implementadas
- [x] Fase 4d: Template ready (comentários + decisão SETIC #10)
- [x] Fase 5: Guia operacional completo (deploy, ops, troubleshooting)
- [ ] Testes em DEV/QA: validar estrutura de monitoramento (próximo passo)

---

## Cronograma Recomendado

```
2026-09-28    ← Documento SETIC revisado recebido; dúvidas críticas #1/#5 resolvidas
 ↓
2026-09-29    Fase 3 pode iniciar já (bloqueador de regras removido)
 ↓
2026-10-10    Fase 3 executada (testes com ~100k)
 ↓
2026-09-30    Dúvidas #8/#10/#11 confirmadas — nenhum bloqueador formal restante
 ↓
2026-10-17    Fase 4a–4c operacional + Fase 3 aprovada
 ↓
2026-10-24    Deploy em produção (com contingência/rollback)
```

---

## Contatos e Escalação

**Implementação:** Eric Lmello (eric.lmello2024@gmail.com)
**SETIC/Negócio:** [email/contato fornecido no documento original]
**Tecnologia:** [DBA, DevOps conforme ambiente]

---

## Referência de Arquivos

**Análise:**
- `docs/analisa_criterios_audiencias_setic.md` — Análise completa com bugs encontrados

**Documentação de Dúvidas:**
- `docs/DUVIDAS_SETIC_Criterios_Audiencias.md` — 11 dúvidas estruturadas (7 resolvidas total/parcial)

**Implementação:**
- `sql/audiencias_realizadas_v2_draft.sql` — Query v2 (Fase 2)
- `docs/PLANO_TESTES_FASE_3.md` — Plano detalhado de testes (Fase 3)
- `sql/tabelas_monitoramento_fase4.sql` — Infraestrutura de monitoramento (Fase 4)

**Status:**
- `docs/RESPOSTAS_SETIC_Cronograma.md` — Rastreamento de respostas
- `docs/STATUS_ENTREGAS_FASES.md` — Este arquivo (visão geral por fase)

---

**Última atualização:** 2026-09-30 (dúvidas #8/#10/#11 confirmadas pela SETIC — 9 de 11 resolvidas)  
**Próxima revisão:** Quando Fase 3 (testes) for executada, ou dúvidas residuais #2/#3 forem confirmadas
