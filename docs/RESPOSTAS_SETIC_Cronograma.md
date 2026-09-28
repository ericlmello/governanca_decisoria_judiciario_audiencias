# Respostas SETIC — Critérios de Audiências

**Status:** Consolidando respostas do SETIC/Negócio às dúvidas levantadas em 2026-09-24 (11 dúvidas após revisão de 2026-09-28)

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

## ⚠️ Parcialmente Resolvidas

### Dúvida #3: Instrução Sem Diligência e Sem Julgamento

**Resposta parcial (documento revisado, 2026-09-28):** Nova regra explícita "sem diligência +
Encerramento de Instrução designado → Adiada". Resolve o sub-caso de Encerramento de Instrução
redesignado sem sinal de diligência.

**Resíduo ainda pendente:** Instrução sem NENHUM sinal registrado (nem diligência, nem
Julgamento/Conciliação, nem Encerramento de Instrução designado) continua sem rótulo explícito no
documento. Cai em Adiada por omissão — caso residual raro, ainda aguardando confirmação SETIC.

**Implicação na query v2:** ✅ Implementado (regra 4c do `CASE`, `audiencias_realizadas_v2_draft.sql`)

**Data da resposta:** 2026-09-28 (parcial)

---

### Dúvida #2: UNA Seguida de Tipo Fora do Escopo

**Escopo reduzido (documento revisado, 2026-09-28):** UNA → Encerramento de Instrução direto
(sem diligência) SAIU desta dúvida — o documento esclareceu que segue a mesma avaliação de 3 dias
úteis da bipartição (Adiada por padrão, exceto diligência+Encerramento). Já implementado.

**Resíduo ainda pendente:** UNA → Julgamento ou Conciliação diretamente, **fora** da janela de 3
dias úteis (dentro da janela já é tratado pela regra 3b). Hipótese ainda não confirmada: Efetiva
por analogia com a Inicial.

**Decisão do usuário (2026-09-24, mantida):** "Aplique a regra geral quando não expressa" — UNA
seguida de Julgamento/Conciliação diretamente = **Efetiva**, por analogia com a regra da Inicial.

**Implicação na query v2:** ✅ Já implementado (regra 3d do `CASE` de `classificacao`,
`audiencias_realizadas_v2_draft.sql`) — hipótese ainda não confirmada formalmente pela SETIC.

---

## ⏳ Pendentes

### Dúvida #8: Dias Úteis — Abrangência Municipal

Status: **Aguardando resposta**

Se suspensão vale só em 1 município, deve contar como não-útil:
- **(a) Apenas para varas daquele município** (granulado)
- **(b) Nunca — estado inteiro** (simplificado)
- **(c) Não entra no cálculo** (ignora município)

**Impacto:** Baixo (edge case)

---

### Dúvida #10: Watermark de Carga (`VAR_ULT_DT_AUDIENCIA`) Autorreferente

Status: **Aguardando resposta**

Confirmado pelo usuário que a variável vem de:
```sql
SELECT MAX(dt_audiencia) AS ultima_dt
FROM pai_2_0.audiencias
WHERE status <> 'Programada'
```

Watermark lido da própria tabela de destino → risco de perda silenciosa de audiências
cujas janelas de 3 dias úteis fecham depois de outras do mesmo dia (calendário varia por vara).

Perguntas:
1. É um padrão intencional/conhecido ou não documentado?
2. Existe reprocessamento/backfill já em uso?
3. Existe auditoria periódica que detectaria essa lacuna?

**Impacto:** Alto (perda de dados sem alerta — não é regra de negócio, é mecanismo de carga)

---

### Dúvida #11: [NOVA 2026-09-28] Mapeamento Exato do Tipo "Conciliação"

Status: **Aguardando resposta**

O documento revisado (2026-09-28) introduziu "Conciliação" como sinal válido em 3 pontos
(Inicial, UNA, Instrução) sem especificar qual subtipo — Conciliação em Conhecimento (ids 1, 32,
20, 33) ou Conciliação em Execução (ids 2, 34, 36, 21, 35, 37).

**Hipótese implementada:** apenas Conciliação em Conhecimento (fase compatível temporalmente com
os demais tipos avaliados).

**Impacto:** Médio (afeta 3 regras: Inicial/UNA/Instrução)

---

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
| 2 | UNA → Julgamento/Conciliação direto fora da janela = Efetiva (regra geral) | Implementada; escopo reduzido em 28/09; **ainda enviada à SETIC** | `audiencias_realizadas_v2_draft.sql`, regra 3d do `CASE` |
| 4 | Tipo 8 "Instrução e Julgamento" = sempre Efetiva | ✅ Confirmada pela SETIC (2026-09-29) | `audiencias_realizadas_v2_draft.sql`, regra 1.5 do `CASE` |
| 11 | Conciliação = só "em Conhecimento" (ids 1,32,20,33) | Implementada; **NOVA pergunta enviada à SETIC** | `audiencias_realizadas_v2_draft.sql`, `parametros.tipo_conciliacao` |

---

## Próximos Passos

- [x] Enviar `docs/DUVIDAS_SETIC_Criterios_Audiencias.md` ao SETIC/Negócio
- [x] Implementar hipótese das dúvidas #2 e #4 (decisão do usuário: "regra geral quando não expressa")
- [x] **Dúvida #6 (perícia) respondida e TODO removido** (2026-09-25)
- [x] **Documento SETIC revisado recebido — Dúvidas #1, #5 resolvidas, #3 parcial** (2026-09-28)
- [x] Implementar todas as mudanças de regra do documento revisado em `audiencias_realizadas_v2_draft.sql`
- [x] **Dúvida #4 (tipo 8) confirmada pela SETIC** (2026-09-29)
- [ ] Aguardar respostas (dúvidas #2 residual, #3 residual, #8, #10, #11)
- [x] Atualizar este cronograma e `docs/DUVIDAS_SETIC_Criterios_Audiencias.md` conforme respostas chegarem
- [x] **FASE 3 (Testes):** Criar plano abrangente — `docs/PLANO_TESTES_FASE_3.md` (40+ casos de teste, bloqueadores identificados)
- [x] **FASE 4 (Monitoramento):** Implementar tabelas `fato_audiencia_classificada`, `trilha_execucao`, `metrica_integridade` — `sql/tabelas_monitoramento_fase4.sql`
- [ ] Finalizar `audiencias_realizadas_v2_draft.sql` com as respostas restantes de dúvidas críticas (#8, #10, #11)
- [ ] Testes com dados reais (~100k audiências) — ativado após respostas SETIC
- [ ] Colocar em produção com suporte e runbooks

---

**Última atualização:** 2026-09-29 (Dúvida #4 confirmada pela SETIC — sempre Efetiva)

**Próxima revisão:** Quando dúvidas restantes (#2 residual, #3 residual, #8, #10, #11) forem respondidas
