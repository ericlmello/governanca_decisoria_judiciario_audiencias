# Dúvidas para Clarificação — PAI: Critérios de Classificação de Audiências

**De:** TRT-2 / Engenharia de Dados  
**Para:** SETIC / Núcleo de Governança de Audiências  
**Data:** 2026-09-24 (última atualização: 2026-09-28)  
**Referência:** Documento "PAI - Critérios Audiências SETIC" (Definição de audiências Efetivas, Adiadas e impactos no IAD)

---

## ATUALIZAÇÃO 2026-09-28 — Revisão do Documento SETIC

A SETIC enviou uma versão revisada do documento "PAI - Critérios Audiências SETIC" em 2026-09-28,
que **resolve 3 das dúvidas abaixo** (#1, #3 parcial, #5) e **introduz mudanças de regra** que já
foram implementadas em `sql/audiencias_realizadas_v2_draft.sql`:

- **Conciliação** passou a contar como sinal equivalente a Julgamento (UNA/Instrução) e como tipo
  de audiência subsequente válido (Inicial).
- **Inicial**: novo trigger "ou ocorre a prolação da sentença" — Inicial que termina direto em
  sentença/acordo, sem nova audiência, agora é Efetiva. **Resolve a Dúvida #1.**
- **UNA**: audiências que pulam direto para Encerramento de Instrução (sem diligência) agora
  seguem a MESMA avaliação da bipartição (antes caíam automaticamente em Efetiva pela regra de
  "avançar de categoria" — ver Dúvida #2, escopo agora reduzido).
- **Instrução**: nova regra explícita "sem diligência + Encerramento de Instrução designado →
  Adiada". **Resolve parcialmente a Dúvida #3** (resíduo: Instrução sem nenhum sinal registrado
  continua sem rótulo explícito).
- **Prolação de sentença**: o documento agora lista explicitamente os códigos de movimento para
  sentença COM e SEM resolução de mérito. **Resolve a Dúvida #5.**

Essa atualização também introduziu uma nova pergunta em aberto — ver **Dúvida #11** (mapeamento
exato do tipo de audiência "Conciliação").

---

## Resumo Executivo

Durante a implementação do algoritmo de classificação de audiências (Efetivas × Adiadas) em SQL/PostgreSQL, identificamos **11 pontos que carecem ou careceram de clarificação** no documento original (9 originais + 1 nova em 28/09). Alguns são lacunas explícitas (casos não cobertos pelo texto), outros derivam da necessidade de traduzir as regras para lógica de banco de dados (ambiguidades de sequência, temporalidade ou escopo).

**Status consolidado (2026-09-28):** 7 resolvidas (#1, #5, #6, #7, #9 totalmente; #2 parcialmente reduzida em escopo; #3 parcialmente), 4 pendentes (#2 residual, #4, #8, #10, #11).

**Estrutura deste documento:**
- Cada dúvida está ancorada à seção do documento original onde se origina
- São apresentadas na ordem em que surgem nas regras
- Inclui o impacto técnico (comportamento atual vs. esperado)

---

## 1. Audiência Inicial com Encaminhamento para Acordo / Conclusão Direta — ✅ RESOLVIDA (2026-09-28)
**Seção do documento:** 📋 Audiência Inicial (linha 14–22)

### Regra atual:
> "Designação de audiência posterior de qualquer tipo... → **EFETIVA**"

### Dúvida:
Uma audiência **Inicial** que **não é redesignada** (regra geral não se aplica), mas é seguida de:
- **Conclusão para sentença** (conclusos os autos para homologação de acordo)
- **Homologação de acordo**  
- **Arquivo por extinção**

...contém nova audiência? **Não.** A Inicial "cumpriu seu papel ao gerar encaminhamento" (o acordo ou conclusão direta), mas não designou audiência subsequente.

### Pergunta:
Esses desfechos (Inicial → Acordo/Conclusão, sem nova audiência) contam como **Efetiva**?

### ✅ Resposta (documento revisado, 2026-09-28):
O documento atualizado acrescentou explicitamente **"ou ocorre a prolação da sentença"** como
trigger alternativo da regra da Inicial, ao lado da lista de audiências subsequentes. Confirma-se
que Inicial → sentença/acordo homologado **diretamente**, sem nova audiência, é **EFETIVA**.

### Impacto técnico:
- Query atual (original): Classificava como **Efetiva** (por ausência de sinal de "Adiada")
- Query v2 (antes desta atualização): Classificava como **Adiada** (nenhuma subsequente é encontrada → caía em `ELSE`)
- **Implementado:** nova CTE `sentenca_ou_acordo_sem_janela` (sem janela de 3 dias úteis, igual às
  demais checagens da Inicial) + novo ramo na regra 2 do `CASE` de `classificacao`, em
  `sql/audiencias_realizadas_v2_draft.sql`. Usa a mesma lista de códigos de movimento resolvida
  na Dúvida #5 (sentença com E sem resolução de mérito).

---

## 2. UNA Seguida de Tipo Fora do Documento — ⚠️ ESCOPO REDUZIDO (2026-09-28)
**Seção do documento:** 🔵 Audiência UNA (linha 26–55)

### Regra atual:
Cobre dois cenários:
1. **Mesma categoria redesignada** (UNA → UNA) → ADIADA
2. **Bipartição** (UNA → Instrução) → ADIADA com 3 exceções (linhas 37–55)

### Dúvida:
Uma UNA é seguida de um tipo de audiência **que não está em nenhum dos dois cenários acima**, como:
- Encerramento de Instrução (id_tipo_audiencia = 10)
- Julgamento (id_tipo_audiencia = 4)
- Conciliação / Mediação / outro

### ⚠️ Atualização (documento revisado, 2026-09-28) — Encerramento de Instrução SAI desta dúvida:
O documento revisado esclareceu que "nenhum movimento + designa Instrução **ou encerramento de
instrução**" → ADIADA. Ou seja, **UNA → Encerramento de Instrução direto (sem diligência) NÃO é
mais parte desta dúvida** — passa a seguir a MESMA avaliação de 3 dias úteis da bipartição
UNA→Instrução (diligência+Encerramento exigidos para Efetiva). Já implementado em
`sql/audiencias_realizadas_v2_draft.sql` (regras 3a–3c do `CASE`, condição ampliada para
`tipo_instrucao || tipo_encerramento_instrucao`).

**O que resta em aberto:** UNA seguida de **Julgamento ou Conciliação diretamente** (pulando a
Instrução) — esse caso não tem regra explícita no documento. Continua como hipótese não
confirmada (ver abaixo), mas o escopo do risco caiu bastante: Julgamento/Conciliação designados
dentro da janela de 3 dias úteis já são capturados pela regra 3b (Efetiva, mesmo tratamento do
"sem diligência + Julgamento" da bipartição) — a regra 3d (hipótese abaixo) só se aplica como
rede de segurança para esses tipos FORA da janela de 3 dias úteis.

### Hipótese de trabalho (para confirmar, não assumida na query):
Por analogia com a Audiência Inicial (que tem regra explícita: qualquer subsequente entre os
tipos listados = Efetiva) e com o espírito geral do documento (repetir a mesma categoria =
Adiada; **avançar** de categoria = Efetiva), UNA seguida de Julgamento ou Conciliação
**diretamente**, fora da janela de 3 dias úteis, poderia ser **Efetiva** — o processo avançou de
estágio, não regrediu nem repetiu.

### Pergunta:
**Confirma a hipótese acima (UNA → Julgamento/Conciliação direto, fora da janela = Efetiva, por
analogia com a Inicial)?** Ou esse caso deveria ser tratado como Adiada por falta de regra
explícita?

### Impacto técnico:
Ramo "3d" do `CASE` (Efetiva por eliminação) — hoje é rede de segurança residual, de baixo
impacto esperado (a maioria dos casos reais de Julgamento/Conciliação após UNA cai dentro da
janela de 3 dias úteis e já é tratada pela regra 3b).

---

## 3. Instrução Sem Diligência e Sem Julgamento — ⚠️ PARCIALMENTE RESOLVIDA (2026-09-28)
**Seção do documento:** 📑 Audiência de Instrução (linha 57–73)

### Regra atual:
Cobre dois cenários:
1. **Mesma categoria redesignada** (Instrução → Instrução) → ADIADA  
2. **Com diligência + Encerramento de Instrução designado** → EFETIVA
3. **Sem diligência + Julgamento designado** → EFETIVA

### Dúvida:
Uma Instrução realizada **não é redesignada** (cenário 1 não se aplica) e **também**:
- Não há diligência (perícia/ofício/carta/mandado)
- Não há Julgamento designado

Qual é o status? O documento cita a UNA com um rótulo para esse caso ("bipartição injustificada" → ADIADA), mas a Instrução não tem equivalente explícito.

### Pergunta:
Por analogia com a UNA, seria **Adiada**? Ou existe outra regra?

### ⚠️ Resposta parcial (documento revisado, 2026-09-28):
O documento acrescentou uma nova linha explícita: **"Sem diligências + encerramento da instrução
designado" → ADIADA**. Isso confirma, para o sub-caso específico de "Encerramento de Instrução
redesignado sem sinal de diligência", que o resultado é Adiada (mesma lógica de "bipartição
injustificada" da UNA). Já implementado (`sql/audiencias_realizadas_v2_draft.sql`, regra 4c).

**Resíduo ainda em aberto:** o documento não cobriu o caso de Instrução **sem NENHUM sinal
registrado** — nem diligência, nem Julgamento/Conciliação designado, nem Encerramento de
Instrução designado (isto é, nada acontece depois, nenhuma audiência nova é sequer marcada).
Esse caso residual continua caindo em ADIADA por omissão (`ELSE` do `CASE`), sem confirmação
explícita da SETIC.

### Pergunta remanescente:
Instrução sem qualquer sinal subsequente (nem diligência, nem Julgamento/Conciliação/Encerramento
de Instrução designado) — confirma **Adiada** por omissão, ou existe alguma regra de prazo/tempo
adicional (ex.: aguardar X dias além dos 3 úteis antes de classificar)?

### Impacto técnico:
Caso residual raro na prática (a maioria das Instruções tem algum movimento subsequente em até 3
dias úteis). Query v2 classifica por omissão (ADIADA) — confirmar se é o esperado.

---

## 4. Tipo de Audiência 8: "Instrução e Julgamento"
**Seção do documento:** Escopo geral (linha 6–11)

### Contexto:
Mapeamento de `tb_tipo_audiencia` confirmado:
- **Inicial:** ids 3, 16, 22, 29
- **UNA:** ids 5, 19, 23, 31, 7, 9
- **Instrução:** ids 6, 12, 24, 27
- **Encerramento de Instrução:** ids 10, 25
- **Julgamento:** id 4
- **Id 8** ("Instrução e Julgamento"): ?

### Dúvida:
O tipo 8 não aparece no documento original. Como classificá-lo?

### Hipótese de trabalho (para confirmar, não assumida na query):
Por já conter o julgamento **no mesmo ato**, não há diligência pendente nem necessidade de sinal posterior — diferente da Instrução comum (que precisa de um sinal futuro para provar que "funcionou"), o tipo 8 já entrega o resultado na própria audiência. Isso o aproxima do caso já levantado na dúvida #1 (UNA/Inicial sem nova audiência, mas com sentença/acordo = Efetiva): audiência que se resolve sozinha não deveria depender de localizar uma audiência subsequente.

**Ressalva:** se o tipo 8 for **redesignado** como novo tipo 8 (mesma categoria), isso sinaliza que o julgamento **não** ocorreu no ato original — nesse caso a regra geral de "mesma categoria redesignada = Adiada" deveria ter prioridade sobre a hipótese de "sempre Efetiva".

### Opções:
a) **Sempre Efetiva** (exceto se redesignado como novo tipo 8 → Adiada pela regra geral) — hipótese acima  
b) Segue a árvore completa da **Instrução** (verifica diligência + Encerramento, ou Julgamento designado)  
c) Segue a árvore da **UNA** (mesma lógica)  
d) Regra própria (qual?)  
e) Tipo 8 fica **fora do escopo avaliado** (como Conciliação/Mediação já ficam)

### Pergunta:
**Confirma a opção (a)?** Se não, qual das outras se aplica?

### Impacto técnico:
Query v2 atual trata como tipo desconhecido → cai em ADIADA por omissão. Se (a), adicionar ramo de prioridade máxima "Efetiva" (após checar redesignação de mesma categoria); se (b)/(c), aplicar a árvore correspondente; se (e), remover da população avaliada (`tipo_inicial`/`tipo_una`/`tipo_instrucao`).

---

## 5. Sentença Terminativa ("Extinção") × Sentença de Mérito — ✅ RESOLVIDA (2026-09-28)
**Seção do documento:** 🔵 Audiência UNA, Movimentos Monitorados (linha 81–84)

### Regra atual:
> "...Prolação de sentença" (código de movimento esperado)

### Contexto:
Os movimentos de "Prolação de sentença" mapeados (hipótese anterior) eram:
- **Mérito:** id 219 (Procedência), 220 (Improcedência), 221 (Procedência em Parte), 50110 e 50118
- **Terminativa:** id 456 (Extinção), 458–465 (causas de extinção), 454 (Indeferimento), 50126 (Julgamento Antecipado Parcial)

A **sentença terminativa** (extinção sem resolução do mérito) também **encerra a fase de conhecimento** e permite que o processo siga para a fase de execução — igual a uma sentença de mérito.

### Pergunta:
A "Prolação de sentença" deve incluir sentença terminativa (extinção)? Ou apenas sentença de mérito?

### ✅ Resposta (documento revisado, 2026-09-28):
**SIM — ambas contam.** O documento atualizado trouxe a lista COMPLETA e oficial de códigos de
movimento, substituindo a hipótese anterior:

- **Com resolução do mérito** (guarda-chuva 385): 219 (procedente), 220 (improcedente), 221
  (procedente em parte), 442, 444, 446, 448, 450, 452, 455, 466 (homologada transação/acordo),
  471, 11795, 50103
- **Sem resolução do mérito / terminativa** (guarda-chuva 218): 454 (indeferida petição inicial),
  457, 458, 459, 460, 461, 462, 463, 464, 465, 472, 473 (diversas causas de extinção)

Os códigos 50110/50118 usados na hipótese anterior **não aparecem** na lista oficial — foram
removidos; o código correto para "liminarmente improcedente" é **50103**.

### Impacto técnico:
Implementado em `sql/audiencias_realizadas_v2_draft.sql` (CTEs `movimentos_julgamento` e
`sentenca_ou_acordo_sem_janela`) — lista completa de 27 códigos substituindo a lista parcial
anterior (5 códigos, só mérito).

---

## 6. Perícia Ativa: Avaliação em Qual Momento? — ✅ RESOLVIDA (2026-09-25)
**Seção do documento:** 📋 Movimentos Monitorados, linha 76 e 📑 Audiência de Instrução, linha 62

### Regra atual:
> "Perícia ativa (Perito designado e laudo da perícia em aberto (status != finalizado e **prazo válido/prazo não vencido**)"

### Contexto técnico:
A "perícia ativa" é avaliada como **estado atual** (data de hoje), não como estado "dentro da janela de 3 dias úteis". Exemplo:
- Audiência realizada em 15/01
- Perícia marcada em 14/01 (dentro do prazo, dentro da janela)
- Data de apuração da query: 22/01
- Status da perícia em 22/01: "laudo entregue" (encerrado)
- **Resultado:** Deixa de contar como diligência → a Instrução pode virar Adiada

### Pergunta:
A condição "perícia ativa" deveria ser:
- **(a) Estado na data de apuração (hoje)** — como a query implementa agora
- **(b) Estado no final da janela de 3 dias úteis** — determinístico, viável em reprocessamento
- **(c) Perícia marcada dentro da janela, independente de status atual** — apenas verifica se foi iniciada

### ✅ Resposta (2026-09-25):
**Opção (c)** — perícia conta como diligência se foi **marcada** (`dt_marcacao`) dentro da janela
de 3 dias úteis, independente de status atual ou de quando o laudo for finalizado.

### Impacto técnico:
Já estava correto em `sql/audiencias_realizadas_v2_draft.sql` (CTE `movimentos_diligencia`,
condição `pp.dt_marcacao BETWEEN ...`) — TODO(confirmar) removido do código.

---

## 7. "Qualquer Audiência Subsequente" da Inicial: Qual Escopo? — ✅ RESOLVIDA (2026-09-24)
**Seção do documento:** 📋 Audiência Inicial (linha 14–21)

### Regra atual:
> "O Magistrado determina a realização de **qualquer audiência subsequente**:
> - UNA
> - Instrução
> - Encerramento de Instrução
> - Julgamento
> → **EFETIVA**"

### Dúvida:
A expressão "qualquer audiência subsequente" é literal (qualquer tipo, inclusive Conciliação, Mediação, Inquirição) ou restrita aos quatro tipos listados?

### Contexto:
- Audiência Inicial seguida de Conciliação em Conhecimento (tipo 1) — conta como Efetiva?
- Audiência Inicial seguida de Mediação (tipo 13) — conta como Efetiva?

### Pergunta:
Confirmar se "qualquer" é:
- **(a) Restrita aos 4 tipos listados** (UNA, Instrução, Encerramento, Julgamento)
- **(b) Verdadeiramente qualquer tipo** (literal)

### ✅ Resposta (2026-09-24):
**Opção (a)** — restrita aos 4 tipos listados (UNA, Instrução, Encerramento de Instrução,
Julgamento). **Atualização (2026-09-28):** o documento revisado adicionou explicitamente
**Conciliação** como 5º tipo aceito na lista da Inicial, e **implementação atual já cobre
qualquer subsequente sem filtro de tipo** (ver `proxima_audiencia`, que não restringe por tipo) —
na prática a Inicial já era mais permissiva que a resposta (a) sugeria, e a inclusão de
Conciliação no documento confirma que essa permissividade está alinhada à intenção da SETIC.

### Impacto técnico:
Query v2 já implementa corretamente (nenhuma mudança necessária).

---

## 8. Dias Úteis: Abrangência Municipal
**Seção do documento:** 📑 Audiência de Instrução (linha 62–67) e tabela "Movimentos Monitorados" (linha 75)

### Contexto técnico:
O cálculo de "3 dias úteis" usa `pje.tb_calendario_eventos`, que tem sinalizadores:
- `in_suspende_prazo` — suspende prazos processuais
- `in_suspende_audiencia` — suspende audiências
- `id_orgao_julgador`, `id_estado`, `id_municipio` — escopo geográfico
- `in_abrangencia` — indica se é nacional ou regional

A query v2 implementa: dia útil = `(in_suspende_prazo != 'S') AND (in_suspende_audiencia != 'S')`  
**Escopo:** Nacional (nulo) **ou** Estado 26 (São Paulo).

### Dúvida:
Se um registro de `tb_calendario_eventos` suspender audiências **apenas em um município específico** (ex.: SP capital, id_municipio = 3509), esse dia deve contar como não-útil:
- **(a) Apenas para as varas daquele município** — granulado
- **(b) Nunca — trata como se o estado inteiro estivesse em recesso** — simplificado  
- **(c) Não entra no cálculo** — ignora suspensão municipal

### Pergunta:
Qual é o escopo desejado?

### Impacto técnico:
Query v2 atual ignora `id_municipio` (opção c). Se a resposta for (a), precisará de revisão para filtrar por vara/órgão julgador.

---

## 9. [Informativo] Tipos 7 e 9: "RS" = "Rito Sumário"? — ✅ RESOLVIDA (2026-09-24)
**Seção do documento:** Escopo geral e tipo UNA

### Contexto:
Dois tipos de audiência têm nomes ambíguos:
- `id_tipo_audiencia = 7`: "UNA-RS ou Justificação Prévia"
- `id_tipo_audiencia = 9`: "UNA - RS"

"RS" provavelmente significa "Rito Sumário" (terceiro rito no direito trabalhista, distinto de "Sumaríssimo"). Já estão mapeados como **UNA** na query v2.

### Contexto:
A query original não diferencia ritos (ordinário/sumário/sumaríssimo) — ela só diferencia "sumaríssimo" porque há versões específicas de Inicial/UNA/Instrução para esse rito. A existência de "RS" sugere um terceiro rito.

### Pergunta:
Confirmar: "RS" = "Rito Sumário" (correto) ou significa outra coisa? Se incorreto, qual seria a classificação correta desses dois tipos?

### ✅ Resposta (2026-09-24):
Confirmado — "RS" = "Rito Sumário" (terceiro rito trabalhista, CLT/Lei 5.584/70). Ids 7 e 9
permanecem mapeados como UNA.

### Impacto técnico:
Classificação de negócio confirmada, mapeamento de `tipo_una` já estava correto — nenhuma mudança necessária.

---

## 10. Watermark de Carga (`VAR_ULT_DT_AUDIENCIA`) É Autorreferente — Risco de Perda Silenciosa
**Seção do documento:** Não se aplica às regras de negócio — é sobre o mecanismo de carga incremental que alimenta a tabela `pai_2_0.audiencias`.

### Contexto:
A variável que delimita a carga incremental (`VAR_ULT_DT_AUDIENCIA`) é obtida com:
```sql
-- maior data de audiência excluindo as programadas
SELECT MAX(dt_audiencia) AS ultima_dt
FROM pai_2_0.audiencias
WHERE status <> 'Programada'
```
Ou seja, o valor é lido **da própria tabela de destino** que a carga grava (padrão "watermark autorreferente"), não de um parâmetro/controle externo independente.

### Por que isso é um risco:
- O limite de "3 dias úteis" varia por vara/comarca (calendário local de suspensão de prazo/audiência).
- Duas audiências do **mesmo dia**, em varas diferentes, podem ter janelas de 3 dias úteis fechando em datas diferentes.
- Assim que **qualquer** audiência daquele dia (ou de dia posterior) for gravada em `pai_2_0.audiencias`, o `MAX(dt_audiencia)` avança.
- A partir daí, o filtro `dt_inicio > ultima_dt` passa a **excluir permanentemente** qualquer outra audiência daquele mesmo dia que ainda não tenha sido processada — mesmo que a janela dela feche depois.
- Não há mecanismo de retry: uma vez que o `MAX` ultrapassa uma data, ela nunca mais volta a ser candidata na carga seguinte.

### Consequência prática:
Perda **silenciosa** de audiências — sem erro, sem log de falha, elas simplesmente nunca aparecem no resultado. É mais provável perto de janelas divergentes entre varas (ex.: recesso forense não afeta todas as comarcas de forma uniforme).

### Pergunta:
1. Esse padrão de watermark autorreferente é **intencional** (aceita esse risco como conhecido) ou é um comportamento não documentado da carga atual?
2. Existe algum mecanismo de reprocessamento/backfill já em uso para mitigar esse tipo de perda (ex.: reprocessar os últimos N dias a cada carga, upsert por chave)?
3. Há alguma auditoria/reconciliação periódica que compare a população total de audiências elegíveis (`pje`) com o que foi de fato carregado em `pai_2_0.audiencias`, capaz de detectar esse tipo de lacuna?

### Impacto técnico:
Recomendação já adotada na v2 (aguardando confirmação do padrão de carga): trocar o corte exato por uma **sobra de segurança** (ex.: `MAX(dt_audiencia) - 45 dias`, não o valor exato) combinada com **upsert** na chave `(id_processo_audiencia, versao_regra)`, para que reprocessar um período já carregado apenas atualize (sem duplicar) e audiências "esquecidas" voltem a ser avaliadas em cargas futuras.

---

## 11. [NOVA — 2026-09-28] Mapeamento Exato do Tipo "Conciliação"
**Seção do documento:** 📋 Audiência Inicial, 🔵 Audiência UNA, 📑 Audiência de Instrução (documento revisado 2026-09-28)

### Contexto:
A revisão do documento de 2026-09-28 introduziu "Conciliação" como sinal válido em três pontos:
como audiência subsequente aceita para a Inicial, como sinal equivalente a Julgamento na UNA/
Instrução ("sem diligência + Julgamento designado **ou Conciliação**"), e como uma das
"marcações de audiência" monitoradas ("Marcação de audiência de julgamento / encerramento de
instrução / conciliação").

O documento não especifica QUAL subtipo de Conciliação é relevante. O catálogo de
`tb_tipo_audiencia` tem dois grupos distintos:
- **Conciliação em Conhecimento** (ids 1, 32, 20, 33) — fase de conhecimento, mesma fase de
  Inicial/UNA/Instrução
- **Conciliação em Execução** (ids 2, 34, 36, 21, 35, 37) — fase de execução, pós-julgamento

### Hipótese de trabalho (implementada, não confirmada):
Usamos apenas **Conciliação em Conhecimento** (1, 32, 20, 33). Conciliação em Execução ocorre
temporalmente muito depois (fase de execução, após trânsito em julgado), incompatível com sinais
restritos a poucos dias úteis após uma audiência de conhecimento.

### Pergunta:
Confirma que "Conciliação", nos três contextos acima, se refere apenas à **Conciliação em
Conhecimento**? Ou deveria incluir também Conciliação em Execução em algum desses contextos?

### Impacto técnico:
Implementado em `sql/audiencias_realizadas_v2_draft.sql` (`parametros.tipo_conciliacao = ARRAY[1,
32, 20, 33]`). Se a resposta incluir Conciliação em Execução, adicionar ids 2, 34, 36, 21, 35, 37
ao array.

---

## Anexo: Tabela de Referência Rápida

| # | Assunto | Linha do Documento | Status na v2 | Risco |
|---|---|---|---|---|
| 1 | Inicial sem nova audiência (acordo/conclusão) | 14–22 | ✅ Resolvida (2026-09-28) — implementada | — |
| 2 | UNA → Julgamento/Conciliação direto fora da janela — **hipótese: Efetiva**, por confirmar (escopo reduzido em 28/09) | 26–55 | Adiada por omissão fora da janela | **Baixo** (residual, maioria já coberta pela janela) |
| 3 | Instrução sem diligência e sem Julgamento | 57–73 | ⚠️ Parcialmente resolvida (2026-09-28) — resíduo: nenhum sinal registrado | **Baixo** (residual, caso raro) |
| 4 | Tipo 8 "Instrução e Julgamento" — **hipótese: sempre Efetiva** (exceto redesignação) | — | Hipótese implementada, não confirmada | **Médio** (fora do escopo original) |
| 5 | Sentença terminativa × sentença de mérito | 81–84 | ✅ Resolvida (2026-09-28) — implementada, 27 códigos | — |
| 6 | Perícia: avaliada quando? | 76 | ✅ Resolvida (2026-09-25) — implementada | — |
| 7 | Inicial → "qualquer" audiência (literal ou restrito?) | 14–21 | ✅ Resolvida (2026-09-24) — implementada | — |
| 8 | Dias úteis + abrangência municipal | 62–67 | Ignora município | **Baixo** (edge case) |
| 9 | [Informativo] RS = Rito Sumário | Escopo | ✅ Resolvida (2026-09-24) — confirmado | — |
| 10 | Watermark autorreferente — perda silenciosa de audiências | — (mecanismo de carga) | Herda o padrão atual (`MAX(dt_audiencia)` exato) | **Alto** (perda de dados sem alerta) |
| 11 | [NOVA 2026-09-28] Mapeamento exato de "Conciliação" | — | Hipótese implementada (só Conciliação em Conhecimento) | **Médio** (afeta 3 regras: Inicial/UNA/Instrução) |

**Pendentes reais (aguardando SETIC):** #4, #8, #10, #11. **Residuais de baixo risco:** #2, #3.

---

## Processo de Resposta Sugerido

Para cada dúvida, esperamos:
1. **Clarificação textual** (uma frase)
2. **Exemplos concretos**, se aplicável (caso de uso)
3. **Referência a regra existente**, se a resposta estiver em outra parte do documento

---

**Documento preparado por:** TRT-2 / Engenharia de Dados  
**Data de preparação:** 2026-09-24  
**Última atualização:** 2026-09-28 (documento SETIC revisado — 3 dúvidas resolvidas, 1 nova introduzida)  
**Versão de referência:** v2 draft do algoritmo (sql/audiencias_realizadas_v2_draft.sql)
