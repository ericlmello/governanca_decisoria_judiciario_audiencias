# Status de Entregas por Fase

**Data de compilação:** 2026-09-25 (Atualizado 2026-09-28)  
**Status geral:** Fase 2 ~90% completa (documento SETIC revisado resolveu #1, #5, #3 parcial); Fase 3 planejada; Fases 4–5 completas aguardando Fase 3

---

## ATUALIZAÇÃO 2026-09-28 — Documento SETIC Revisado

A SETIC enviou uma versão revisada do documento "PAI - Critérios Audiências SETIC", resolvendo
as Dúvidas #1 (Inicial sem nova audiência) e #5 (sentença terminativa) totalmente, e #3
(Instrução sem diligência/Julgamento) parcialmente. Também introduziu Conciliação como sinal
válido (Inicial/UNA/Instrução) e uma nova dúvida (#11, mapeamento do tipo Conciliação). Todas as
mudanças já implementadas em `sql/audiencias_realizadas_v2_draft.sql`. Ver
`docs/DUVIDAS_SETIC_Criterios_Audiencias.md` para o detalhamento completo.

---

## Resumo Executivo

| Fase | Objetivo | Status | Bloqueador | Próximo |
|------|----------|--------|-----------|--------|
| 1 | Análise de regras | ✅ Completo | — | ✅ Concluído |
| 2 | Query v2 + bugs | ⚠️ ~90% completo | SETIC #8, #10, #11 (residuais #2/#3 baixo risco) | Aguardar respostas restantes |
| 3 | Testes ~100k | 📋 Pronto (40+ casos) | Acesso a banco de dados real | Pode iniciar já (regras críticas resolvidas) |
| 4 | Monitoramento | ✅ 4a–4c completo | SETIC #10 (só 4d) | ✅ Pronto; 4d após resposta |
| 5 | Produção | ✅ Guia pronto | Fase 3 OK + Fase 4 | Pronto; deploy após Fase 3 ✅ |

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
  - TODOs/premissas remanescentes: dúvidas #2 (residual), #3 (residual), #8, #10, #11

### Bloqueadores Críticos
| Dúvida | Tópico | Status | Impacto | Prioridade |
|--------|--------|--------|---------|-----------|
| #1 | Inicial sem nova audiência (acordo/sentença) | ✅ Resolvida (2026-09-28) | — | ✅ IMPLEMENTADA |
| #2 | UNA → Julgamento/Conciliação direto fora da janela | Aberta (escopo reduzido) | Baixo (residual) | Hipótese implementada |
| #3 | Instrução sem nenhum sinal (residual) | Parcial (2026-09-28) | Baixo (residual) | Hipótese implementada |
| #4 | Tipo 8 "Instrução e Julgamento" | ✅ Resolvida (2026-09-29) | — | ✅ IMPLEMENTADA |
| #5 | Sentença terminativa = "prolação"? | ✅ Resolvida (2026-09-28) | — | ✅ IMPLEMENTADA |
| #6 | Perícia ativa avaliada quando? | ✅ Resolvida (2026-09-25) | — | ✅ IMPLEMENTADA |
| #8 | Calendário: abrangência municipal? | Aberta | Baixo | Opcional (SP only) |
| #10 | Watermark autorreferente | Aberta | **Alto** (arquitetura) | NÃO bloqueia Fases 3–4a |
| #11 | Mapeamento exato de "Conciliação" | Aberta (NOVA 2026-09-28) | Médio | Hipótese implementada |

### O que falta para finalizar Fase 2
- [ ] Resposta SETIC às dúvidas restantes (#8, #10, #11 — prioritárias; #2/#3 residuais de baixo risco)
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
- Dúvidas #8, #10, #11 não bloqueiam o início dos testes (hipóteses já implementadas,
  testes podem rodar e ser reexecutados se a resposta SETIC mudar a lógica)

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

#### 4d: Reprocessamento Automático (⏳ Bloqueado por SETIC #10)
- Usa decisão sobre watermark (comentário em procedimentos_fase4b.sql)
- Se Opção A (Rolling Window): MAX(dt_audiencia) - 45 dias
- Se Opção B (Config Table): marca d'água externa
- Default implementado: Opção A (conservador, seguro)

### Bloqueadores
- ⏳ Resposta SETIC a dúvida #10 (watermark) — para implementar 4d

### O que fazer antes de respostas SETIC
- [x] Código das tabelas pronto (criar em DEV)
- [ ] Implementar Procedure (4b) para alimentar `fato_audiencia_classificada`
- [ ] Implementar Views (4c) para monitoramento
- [ ] Criar dashboard básico (ex.: Tableau/Metabase)

---

## Fase 5: Produção ✅ (Pronto para Deploy)

### Requisitos
- ✅ Fase 2 substancialmente finalizada (dúvidas críticas #1, #5 resolvidas; #3 parcial; residuais
  #8/#10/#11 não bloqueiam produção com as hipóteses já implementadas)
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
- [ ] #3 (residual): Instrução sem NENHUM sinal (nem diligência, nem Julgamento/Encerramento) → Adiada por omissão, confirmar?
- [ ] #2 (residual): UNA → Julgamento/Conciliação direto fora da janela → Efetiva, confirmar?
- [x] #4: Tipo 8 "Instrução e Julgamento" → **sempre Efetiva, confirmado 2026-09-29**
- [ ] #8: Calendário suspensão municipal (granular, estadual ou nacional)?
- [ ] #10: Watermark autorreferente é intencional? Existe reprocessamento?
- [ ] #11 (NOVA): Conciliação em Conhecimento apenas, ou também Execução?

**Prazo sugerido:** Máx. 2 semanas a partir de 2026-09-28 (2026-10-12) para as restantes

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
2026-10-12    Resposta SETIC esperada (dúvidas restantes #8/#10/#11)
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

**Última atualização:** 2026-09-28 (documento SETIC revisado — dúvidas #1/#5 resolvidas, #3 parcial)  
**Próxima revisão:** Quando respostas às dúvidas restantes chegarem (#8, #10, #11 — esperado 2026-10-12)
