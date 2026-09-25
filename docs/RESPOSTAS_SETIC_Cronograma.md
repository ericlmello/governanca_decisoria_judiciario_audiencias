# Respostas SETIC — Critérios de Audiências

**Status:** Consolidando respostas do SETIC/Negócio às 9 dúvidas levantadas em 2026-09-24

---

## ✅ Resolvidas

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

## 🔶 Decididas internamente (implementadas; aguardando confirmação formal da SETIC)

### Dúvida #2: UNA Seguida de Tipo Fora do Escopo

**Decisão do usuário (2026-09-24):** "Aplique a regra geral quando não expressa" — UNA seguida de
Encerramento de Instrução ou Julgamento diretamente (pulando a Instrução) = **Efetiva**, por
analogia com a regra da Inicial (avançar de categoria = Efetiva).

**Implicação na query v2:** ✅ Já implementado (regra 3d do `CASE` de `classificacao`,
`audiencias_realizadas_v2_draft.sql`)

**Continua no questionário enviado à SETIC** como pergunta fechada (confirmar/rejeitar a
hipótese já implementada) — a decisão do usuário destrava a implementação, mas não substitui a
confirmação formal do negócio sobre uma regra que afeta métrica reportada.

---

### Dúvida #4: Tipo 8 "Instrução e Julgamento"

**Decisão do usuário (2026-09-24):** "Aplique a regra geral quando não expressa" — tipo 8 tem
regra própria: **sempre Efetiva** (exceto se redesignado como novo tipo 8, que cai na regra geral
de mesma categoria = Adiada).

**Implicação na query v2:** ✅ Já implementado (regra 1.5 do `CASE` de `classificacao`; tipo 8
adicionado à população avaliada via novo array `tipo_instrucao_julgamento`)

**Continua no questionário enviado à SETIC** como pergunta fechada, mesmo motivo da dúvida #2.

---

## ⏳ Pendentes

### Dúvida #1: UNA e Inicial Sem Nova Audiência

Status: **Aguardando resposta**

Exemplo: Inicial → Acordo homologado (sem nova audiência). Efetiva ou Adiada?

**Impacto:** Alto (possível regressão vs. query original)

---

### Dúvida #3: Instrução Sem Diligência e Sem Julgamento

Status: **Aguardando resposta**

Pergunta: Por analogia com UNA, seria Adiada? Ou existe outra regra?

**Impacto:** Médio

---

### Dúvida #5: Sentença Terminativa (Extinção) Conta Como "Prolação de Sentença"?

Status: **Aguardando resposta**

Exemplo: Extinção do processo sem resolução do mérito. Vale como sinal de Efetiva?

**Impacto:** Médio

---

### Dúvida #6: Perícia Ativa — Avaliada Quando?

Status: **Aguardando resposta**

Opções:
- **(a) Data de apuração (hoje)** — reprocessar pode mudar histórico
- **(b) Final da janela de 3 dias úteis** — determinístico
- **(c) Marcada dentro da janela, independente de status atual** — apenas iniciar

**Impacto:** Médio (define semântica de reprocessamento)

---

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

## Processo de Consolidação

1. **Documento enviado:** `docs/DUVIDAS_SETIC_Criterios_Audiencias.md` (2026-09-24)
2. **Respostas esperadas via:** Email / Chamado SETIC / Reunião de Negócio
3. **Atualização deste arquivo:** À medida que cada resposta chegar
4. **Implementação na query v2:** Após consolidação de respostas críticas (dúvidas #1–6)

---

## Decisões Internas

| Dúvida | Decisão | Status | Implementada em |
|--------|---------|--------|-----------------|
| 7 | Restrito aos 4 tipos listados | Encerrada, não aguarda SETIC | `audiencias_realizadas_v2_draft.sql:15` |
| 9 | RS = Rito Sumário | Encerrada, não aguarda SETIC | `audiencias_realizadas_v2_draft.sql:62,68–71` |
| 2 | UNA → tipo fora do escopo = Efetiva (regra geral) | Implementada; **ainda enviada à SETIC** como pergunta fechada (afeta métrica reportada) | `audiencias_realizadas_v2_draft.sql`, regra 3d do `CASE` |
| 4 | Tipo 8 "Instrução e Julgamento" = sempre Efetiva (regra geral) | Implementada; **ainda enviada à SETIC** como pergunta fechada (afeta métrica reportada) | `audiencias_realizadas_v2_draft.sql`, regra 1.5 do `CASE` |

---

## Próximos Passos

- [x] Enviar `docs/DUVIDAS_SETIC_Criterios_Audiencias.md` ao SETIC/Negócio
- [x] Implementar hipótese das dúvidas #2 e #4 (decisão do usuário: "regra geral quando não expressa")
- [ ] Aguardar respostas (dúvidas #1, #2, #3, #4, #5, #6, #8, #10 — #2/#4 já implementadas, aguardam só confirmação formal)
- [ ] Atualizar este cronograma conforme respostas chegarem
- [ ] Finalizar `audiencias_realizadas_v2_draft.sql` com as respostas restantes
- [ ] Implementar tabelas de monitoramento (`fato_audiencia_classificada`, `trilha_execucao`)
- [ ] Testes com dados reais (~100k audiências)
- [ ] Colocar em produção com suporte e runbooks

---

**Última atualização:** 2026-09-25 (dúvidas #2 e #4 decididas e implementadas — "regra geral quando não expressa")

**Próxima revisão:** Quando dúvidas críticas (#1, #3, #5, #6) forem respondidas
