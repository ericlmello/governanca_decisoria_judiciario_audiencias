# Dúvidas para Clarificação — PAI: Critérios de Classificação de Audiências

**De:** TRT-2 / Engenharia de Dados  
**Para:** SETIC / Núcleo de Governança de Audiências  
**Data:** 2026-09-24  
**Referência:** Documento "PAI - Critérios Audiências SETIC" (Definição de audiências Efetivas, Adiadas e impactos no IAD)

---

## Resumo Executivo

Durante a implementação do algoritmo de classificação de audiências (Efetivas × Adiadas) em SQL/PostgreSQL, identificamos **9 pontos que carecem de clarificação** no documento original. Alguns são lacunas explícitas (casos não cobertos pelo texto), outros derivam da necessidade de traduzir as regras para lógica de banco de dados (ambiguidades de sequência, temporalidade ou escopo).

**Estrutura deste documento:**
- Cada dúvida está ancorada à seção do documento original onde se origina
- São apresentadas na ordem em que surgem nas regras
- Inclui o impacto técnico (comportamento atual vs. esperado)

---

## 1. Audiência Inicial com Encaminhamento para Acordo / Conclusão Direta
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

### Impacto técnico:
- Query atual (original): Classifica como **Efetiva** (por ausência de sinal de "Adiada")
- Query v2 (literária): Classifica como **Adiada** (nenhuma subsequente é encontrada → cai em `ELSE`)
- **Esperado:** Confirmar qual é o correto

---

## 2. UNA Seguida de Tipo Fora do Documento
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

### Pergunta:
Qual é o status esperado? O documento não cobre explicitamente. A query v2 classifica como **Adiada** por omissão — é isso correto?

### Impacto técnico:
Falta ramo decisório (cai no `ELSE` genérico). Se a resposta for "segue regra X da Instrução" ou "sempre Efetiva", precisará de ajuste lógico.

---

## 3. Instrução Sem Diligência e Sem Julgamento
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

### Impacto técnico:
Lacuna análoga à dúvida #2. Query v2 classifica por omissão (ADIADA) — confirmar se é o esperado.

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

### Opções:
a) Segue a árvore da **Instrução** (verifica diligência + Encerramento, ou Julgamento designado)  
b) Segue a árvore da **UNA** (mesma lógica)  
c) Regra própria (qual?)  

### Pergunta:
Qual é a intenção do tipo 8 e como deveria ser classificado?

### Impacto técnico:
Query v2 atual trata como tipo desconhecido → cai em ADIADA por omissão. Se for (a), bastará aplicar a lógica de Instrução; se for (b) ou (c), precisará de revisão.

---

## 5. Sentença Terminativa ("Extinção") × Sentença de Mérito
**Seção do documento:** 🔵 Audiência UNA, Movimentos Monitorados (linha 81–84)

### Regra atual:
> "...Prolação de sentença" (código de movimento esperado)

### Contexto:
Os movimentos de "Prolação de sentença" mapeados são:
- **Mérito:** id 219 (Procedência), 220 (Improcedência), 221 (Procedência em Parte), 50110 e 50118
- **Terminativa:** id 456 (Extinção), 458–465 (causas de extinção), 454 (Indeferimento), 50126 (Julgamento Antecipado Parcial)

A **sentença terminativa** (extinção sem resolução do mérito) também **encerra a fase de conhecimento** e permite que o processo siga para a fase de execução — igual a uma sentença de mérito.

### Pergunta:
A "Prolação de sentença" deve incluir sentença terminativa (extinção)? Ou apenas sentença de mérito?

### Impacto técnico:
Query v2 hoje ativa apenas as de mérito (219/220/221/50110/50118). Se terminativas devem contar, descomentar ids 456/458–465/454/50126.

---

## 6. Perícia Ativa: Avaliação em Qual Momento?
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

### Impacto técnico:
Define a semântica de reprocessamento. Com (a), reprocessar mais tarde pode mudar histórico; com (b)/(c), o resultado fica invariante.

---

## 7. "Qualquer Audiência Subsequente" da Inicial: Qual Escopo?
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

### Impacto técnico:
Query v2 implementa (a). Se for (b), remover o filtro por tipo.

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

## 9. [Informativo] Tipos 7 e 9: "RS" = "Rito Sumário"?
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

### Impacto técnico:
É uma classificação de negócio (sem impacto imediato na lógica SQL). Se for incorreto, ajustar o mapeamento de `tipo_una` na query.

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

## Anexo: Tabela de Referência Rápida

| # | Assunto | Linha do Documento | Status na v2 | Risco |
|---|---|---|---|---|
| 1 | Inicial sem nova audiência (acordo/conclusão) | 14–22 | Adiada por omissão | **Alto** (regressão possível) |
| 2 | UNA → tipo fora do escopo (Enc. Instrução / Julgamento) | 26–55 | Adiada por omissão | **Médio** (lacuna do documento) |
| 3 | Instrução sem diligência e sem Julgamento | 57–73 | Adiada por omissão | **Médio** (lacuna do documento) |
| 4 | Tipo 8 "Instrução e Julgamento" | — | Adiada por omissão | **Médio** (fora do escopo original) |
| 5 | Sentença terminativa × sentença de mérito | 81–84 | Apenas mérito | **Médio** (diferença de negócio) |
| 6 | Perícia: avaliada quando? | 76 | Data de apuração (hoje) | **Médio** (semântica de reprocessamento) |
| 7 | Inicial → "qualquer" audiência (literal ou restrito?) | 14–21 | Restrito aos 4 tipos | **Baixo** (improvável conflito real) |
| 8 | Dias úteis + abrangência municipal | 62–67 | Ignora município | **Baixo** (edge case) |
| 9 | [Informativo] RS = Rito Sumário | Escopo | Assumido como Rito Sumário | **Baixo** (semântica) |
| 10 | Watermark autorreferente — perda silenciosa de audiências | — (mecanismo de carga) | Herda o padrão atual (`MAX(dt_audiencia)` exato) | **Alto** (perda de dados sem alerta) |

---

## Processo de Resposta Sugerido

Para cada dúvida, esperamos:
1. **Clarificação textual** (uma frase)
2. **Exemplos concretos**, se aplicável (caso de uso)
3. **Referência a regra existente**, se a resposta estiver em outra parte do documento

---

**Documento preparado por:** TRT-2 / Engenharia de Dados  
**Data de preparação:** 2026-09-24  
**Versão de referência:** v2 draft do algoritmo (sql/audiencias_realizadas_v2_draft.sql)
