# Respostas SETIC — Critérios de Audiências

**Status:** 12 de 13 dúvidas resolvidas/confirmadas (2026-10-02). Resta apenas a Dúvida #12 (alto impacto, 37,7% de UNA), que tem duas sub-perguntas em aberto.

**Nota de numeração:** A partir de 2026-09-28, os números de dúvida usados neste arquivo foram
alinhados aos do documento canônico `docs/DUVIDAS_SETIC_Criterios_Audiencias.md` (fonte de
verdade). Entradas anteriores deste arquivo referenciavam "Dúvida #2" tanto para Perícia quanto
para "UNA seguida de tipo fora do escopo" — inconsistência histórica, já corrigida abaixo.

---

## ATUALIZAÇÃO 2026-09-28 — Documento SETIC Revisado

A SETIC enviou uma versão revisada do documento "PAI - Critérios Audiências SETIC" que resolve
as Dúvidas **#1** (Inicial sem nova audiência), **#5** (sentença terminativa) totalmente, e **#3**
(Instrução sem diligência/Julgamento) parcialmente — além de introduzir mudanças de regra
(Conciliação como sinal válido) e uma nova dúvida (**#11**, mapeamento do tipo Conciliação). Ver
`docs/DUVIDAS_SETIC_Criterios_Audiencias.md` para o detalhamento completo e
`sql/audiencias_realizadas_v2_draft.sql` para a implementação.

---

## ✅ Resolvidas

### Dúvida #1: Inicial Sem Nova Audiência (Acordo/Sentença Direta)

**Resposta (documento revisado, 2026-09-28):** Novo trigger "ou ocorre a prolação da sentença" —
Inicial que termina direto em sentença/acordo, sem nova audiência, é **Efetiva**.

**Implicação na query v2:** ✅ Implementado — nova CTE `sentenca_ou_acordo_sem_janela` + novo ramo
na regra 2 do `CASE` de `classificacao`, `audiencias_realizadas_v2_draft.sql`.

**Data da resposta:** 2026-09-28

---

### Dúvida #5: Sentença Terminativa Conta Como "Prolação de Sentença"?

**Resposta (documento revisado, 2026-09-28):** SIM — ambas contam. Lista completa e oficial de
27 códigos de movimento fornecida: 14 para "com resolução do mérito" (guarda-chuva 385) e 13 para
"sem resolução do mérito / terminativa" (guarda-chuva 218).

**Implicação na query v2:** ✅ Implementado — CTEs `movimentos_julgamento` e
`sentenca_ou_acordo_sem_janela` atualizadas com a lista completa (substituindo a lista parcial
anterior de 5 códigos, só mérito).

**Data da resposta:** 2026-09-28

---

### Dúvida #6: Perícia Ativa — Avaliada Quando?

**Resposta:** Opção **(c) Marcada dentro da janela, independente de status atual**

Uma perícia conta como "diligência ativa" (sinal de Efetiva) se foi MARCADA (dt_marcacao) dentro da janela de 3 dias úteis, independente de:
- Se será finalizada depois (status muda após a janela)
- Se prazo vencer depois (reprocessar pode mudar)
- Status atual da perícia quando reavaliada

**Implicação na query v2:** ✅ Já implementado e verificado (verifica `pp.dt_marcacao BETWEEN [início] AND [limite_3du]`, linha 356 em `audiencias_realizadas_v2_draft.sql`)

**Ações completadas:**
- ✅ TODO(confirmar) removido (linhas 307-312, agora comentário documentado)
- ✅ Implementação validada como correta

**Data da resposta:** 2026-09-25

---

### Dúvida #7: "Qualquer Audiência Subsequente" da Inicial — Literal ou Restrito?

**Resposta:** Restrito aos 4 tipos listados (UNA, Instrução, Encerramento de Instrução, Julgamento)

**Implicação na query v2:** ✅ Já implementado (linha 15 de `audiencias_realizadas_v2_draft.sql`)

**Data da resposta:** 2026-09-24

---

### Dúvida #9: RS = Rito Sumário?

**Resposta:** Confirmado. "RS" = Rito Sumário (terceiro rito trabalhista, CLT/Lei 5.584/70)

**Implicação na query v2:** ✅ Já implementado (ids 7 e 9 mapeados como UNA, linha 62 e 68–71)

**Data da resposta:** 2026-09-24

---

### Dúvida #4: Tipo 8 "Instrução e Julgamento"

**Resposta (2026-09-29):** Confirmado — sempre Efetiva, exceto se redesignado como novo tipo 8
(cai na regra geral de mesma categoria = Adiada).

**Implicação na query v2:** ✅ Já implementado (regra 1.5 do `CASE` de `classificacao`) —
comentários atualizados de "hipótese" para "confirmado".

**Data da resposta:** 2026-09-29

---

### Dúvida #3: Instrução Sem Diligência e Sem Julgamento

**Resposta (documento revisado, 2026-09-28):** Nova regra explícita "sem diligência + Encerramento
de Instrução designado → Adiada". Resolve o sub-caso de Encerramento de Instrução redesignado sem
sinal de diligência.

**Resíduo (Instrução sem NENHUM sinal registrado) — resposta da área de negócio (2026-10-02):**
Confirmado **Adiada**, validado também com dados reais (01/09–01/10/2026, 40.612 audiências sem
duplicação). Nenhuma mudança de código necessária — já era o comportamento padrão.

**Implicação na query v2:** ✅ Implementado (regra 4c do `CASE`, `audiencias_realizadas_v2_draft.sql`)

**Data da resposta:** 2026-10-02 (resíduo); 2026-09-28 (regra principal)

---

## ✅ Resolvidas (cont.)

### Dúvida #2: UNA Seguida de Tipo Fora do Escopo

**Escopo reduzido (documento revisado, 2026-09-28):** UNA → Encerramento de Instrução direto
(sem diligência) SAIU desta dúvida — o documento esclareceu que segue a mesma avaliação de 3 dias
úteis da bipartição (Adiada por padrão, exceto diligência+Encerramento). Já implementado.

**Resposta final (área de negócio, 2026-10-02):** Confirmado **Efetiva** — UNA → Julgamento ou
Conciliação diretamente, fora da janela de 3 dias úteis, por analogia com a regra da Inicial.

**Implicação na query v2:** ✅ Já implementado (regra 3d do `CASE` de `classificacao`,
`audiencias_realizadas_v2_draft.sql`) — confirmado, sem mudança de código necessária.

---

### Dúvida #13: Instrução Sem Regra de Avanço de Categoria

**Resposta (área de negócio, 2026-10-02):** Confirmado **Efetiva** para os dois cenários — (1)
Instrução seguida de outra audiência fora da janela, (2) diligência + Julgamento/Conciliação
marcado sem Encerramento de Instrução formal.

**Implicação na query v2:** ✅ Implementado — nova regra 4a (diligência+Julgamento sem
Encerramento formal) e nova regra 4d (equivalente à 3d da UNA), em
`sql/audiencias_realizadas_v2_draft.sql`.

---

### Dúvida #8: Dias Úteis — Abrangência Municipal

**Resposta (2026-09-30):** Opção **(a)** — apenas para varas daquele município (granulado).

**Implicação na query v2:** ✅ Implementado (CTE `calendario_3du`, filtro por `id_municipio_vara`)

**Data da resposta:** 2026-09-30

---

### Dúvida #10: Watermark de Carga (`VAR_ULT_DT_AUDIENCIA`) Autorreferente

**Resposta (2026-09-30):** Manter como está — sem rolling window, sem config table. Risco de
perda silenciosa aceito conscientemente.

**Implicação na query v2:** Nenhuma mudança (já usava o watermark exato); propostas de mitigação
em `sql/procedimentos_fase4b.sql` marcadas como "histórico — não implementar".

**Data da resposta:** 2026-09-30

---

### Dúvida #11: Mapeamento Exato do Tipo "Conciliação"

**Resposta (2026-09-30):** Confirmado — apenas Conciliação em Conhecimento (ids 1, 32, 20, 33).
Conciliação em Execução não conta.

**Implicação na query v2:** ✅ Já implementado, hipótese confirmada (`parametros.tipo_conciliacao`)

**Data da resposta:** 2026-09-30

---

## ⏳ Pendentes

### Dúvida #12: UNA Resolvida Diretamente, Sem Nova Audiência

Status: **Aguardando resposta detalhada da área de negócio — tem DUAS sub-perguntas separadas**

**Contexto:** UNA realizada, sem nova audiência designada de nenhum tipo, mas com algum evento de
desfecho registrado em `pje.tb_processo_evento` dentro dos 3 dias úteis seguintes. Hoje nenhuma
regra de UNA cobre esse caso — cai em `ELSE 'Adiada'` por omissão (não existe sinal de "próxima
audiência", único gatilho que as regras 3a-3d sabem reconhecer).

**Validação com dados reais (01/09–01/10/2026):** representa **37,7% de toda a população de UNA**
(10.776 de 28.577 audiências UNA) — o maior achado de todo o projeto de validação.

**Sub-pergunta 1 — caso principal (sentença/homologação de mérito):**
Amostra de 15 processos mostrou os eventos reais que disparam o caso: código 466 "Homologada a
transação" (6 ocorrências), código 51 "Conclusos os autos para julgamento ... Proferir sentença"
(5 ocorrências), e também o código 473 abaixo (4 ocorrências, tratado separadamente). Exemplo real:
processo `1000825-68.2026.5.02.0022`, audiência UNA em 17/09/2026 11:15, evento 466 "Homologada a
transação" registrado às 12:17 do mesmo dia (dentro da janela), nenhuma nova audiência foi marcada
depois.
**Pergunta:** confirma que UNA resolvida direto por sentença de mérito ou homologação de acordo
(transação), sem nenhuma nova audiência, deve ser **Efetiva** — por analogia com a regra já
confirmada para a Inicial (Dúvida #1) e para a própria UNA fora da janela (Dúvida #2)?

**Sub-pergunta 2 — caso específico do código 473 (arquivamento por ausência do reclamante):**
Diferente de sentença ou homologação de acordo, esse evento é a **extinção do processo por falta
da parte** (reclamante não compareceu), não um julgamento de mérito. Exemplo real: processo
`1001326-40.2026.5.02.0016`, audiência UNA em 08/09/2026 11:55, evento 473 registrado no mesmo
dia, seguido do evento 246 "Arquivados os autos definitivamente" (formalização do arquivamento).
**Pergunta:** esse caso também deve ser classificado como Efetiva (a audiência UNA se cumpriu e o
processo terminou por decisão de arquivamento), ou merece tratamento distinto — por exemplo,
porque o reclamante não compareceu, o que poderia sugerir que a PRÓPRIA audiência não ocorreu de
fato (inconsistência com `cd_status_audiencia = 'F'`, que diz que ela foi "Finalizada")?

**Segunda verificação, direcionada (6 casos de UNA sem nenhuma próxima audiência):** 100% tinham
sinal real de encerramento — 5 com código 466 (sub-pergunta 1), 1 com código 473 (sub-pergunta 2).
Nenhum caso "sem sinal nenhum" apareceu nessa sub-amostra — reforça que a lacuna é sistemática.

**Impacto:** Alto (maior volume já identificado, 37,7% de UNA) — enviada à área de negócio em
2026-10-02 junto com o resíduo da Dúvida #3.

---

Fora isso, nenhuma pendência formal restante.

## Processo de Consolidação

1. **Documento enviado:** `docs/DUVIDAS_SETIC_Criterios_Audiencias.md` (2026-09-24)
2. **Respostas esperadas via:** Email / Chamado SETIC / Reunião de Negócio
3. **Atualização deste arquivo:** À medida que cada resposta chegar
4. **Implementação na query v2:** Contínua, à medida que cada resposta chega (não esperamos consolidar todas antes de implementar)

---

## Decisões Internas

| Dúvida | Decisão | Status | Implementada em |
|--------|---------|--------|-----------------|
| 7 | Restrito aos 4 tipos listados (na prática, já mais permissivo) | Encerrada, não aguarda SETIC | `audiencias_realizadas_v2_draft.sql:15` |
| 9 | RS = Rito Sumário | Encerrada, não aguarda SETIC | `audiencias_realizadas_v2_draft.sql:62,68–71` |
| 2 | UNA → Julgamento/Conciliação direto fora da janela = Efetiva (regra geral) | ✅ Confirmada pela área de negócio (2026-10-02) | `audiencias_realizadas_v2_draft.sql`, regra 3d do `CASE` |
| 13 | Instrução sem regra de avanço de categoria = Efetiva | ✅ Confirmada e implementada (2026-10-02) | `audiencias_realizadas_v2_draft.sql`, regras 4a e 4d do `CASE` |
| 4 | Tipo 8 "Instrução e Julgamento" = sempre Efetiva | ✅ Confirmada pela SETIC (2026-09-29) | `audiencias_realizadas_v2_draft.sql`, regra 1.5 do `CASE` |
| 11 | Conciliação = só "em Conhecimento" (ids 1,32,20,33) | ✅ Confirmada pela SETIC (2026-09-30) | `audiencias_realizadas_v2_draft.sql`, `parametros.tipo_conciliacao` |
| 8 | Abrangência municipal = granular (opção a) | ✅ Confirmada pela SETIC (2026-09-30) | `audiencias_realizadas_v2_draft.sql`, CTE `calendario_3du` |
| 10 | Watermark mantido como está (sem rolling window) | ✅ Confirmada pela SETIC (2026-09-30) | Nenhuma mudança de código necessária |

---

## Próximos Passos

- [x] Enviar `docs/DUVIDAS_SETIC_Criterios_Audiencias.md` ao SETIC/Negócio
- [x] Implementar hipótese das dúvidas #2 e #4 (decisão do usuário: "regra geral quando não expressa")
- [x] **Dúvida #6 (perícia) respondida e TODO removido** (2026-09-25)
- [x] **Documento SETIC revisado recebido — Dúvidas #1, #5 resolvidas, #3 parcial** (2026-09-28)
- [x] Implementar todas as mudanças de regra do documento revisado em `audiencias_realizadas_v2_draft.sql`
- [x] **Dúvida #4 (tipo 8) confirmada pela SETIC** (2026-09-29)
- [x] **Dúvidas #8, #10, #11 confirmadas pela SETIC** (2026-09-30) — todas implementadas
- [x] Atualizar este cronograma e `docs/DUVIDAS_SETIC_Criterios_Audiencias.md` conforme respostas chegarem
- [x] **FASE 3 (Testes):** Criar plano abrangente — `docs/PLANO_TESTES_FASE_3.md` (40+ casos de teste, bloqueadores identificados)
- [x] **FASE 4 (Monitoramento):** Implementar tabelas `fato_audiencia_classificada`, `trilha_execucao`, `metrica_integridade` — `sql/tabelas_monitoramento_fase4.sql`
- [x] Finalizar `audiencias_realizadas_v2_draft.sql` — todas as dúvidas críticas respondidas
- [x] Testes com dados reais (01/09–01/10/2026, ~40.6k audiências) — iniciados, sem duplicação
- [x] Dúvida #3 (resíduo) confirmada pela área de negócio — Adiada
- [x] Dúvida #2 confirmada pela área de negócio — Efetiva
- [x] Dúvida #13 confirmada pela área de negócio e implementada (regras 4a/4d)
- [ ] **Dúvida #12:** aguardando resposta às duas sub-perguntas (caso principal + código 473) — maior achado da validação (37,7% de UNA); único item pendente
- [ ] Colocar em produção com suporte e runbooks

---

**Última atualização:** 2026-10-02 (Dúvidas #2, #3 e #13 confirmadas pela área de negócio; Dúvida
#12 detalhada em duas sub-perguntas, ainda pendente)

**Próxima revisão:** Quando Dúvida #12 for respondida (único item pendente)
