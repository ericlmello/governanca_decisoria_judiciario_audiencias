# Análise: Query atual x Novos Critérios SETIC (PAI — Audiências)

Documento de referência: *PAI - Critérios Audiências SETIC.docx* (Critérios de Classificação de
Audiências — Definição de Efetivas/Adiadas e impactos no IAD).

> A coluna "Observação (Fora do script)" do documento foi ignorada, conforme solicitado, por
> se basear em movimentos manuais do PJe que não fazem parte da regra de negócio a implementar.

**Importante:** não foi possível conectar à base `10.2.36.13:3032` (`pje_1grau_cds`) a partir
deste ambiente — é um IP privado (RFC1918), inacessível a partir do container isolado na nuvem
usado nesta sessão (sem VPN/rota para a rede interna do TRT). O usuário rodou as queries de
descoberta manualmente e colou os resultados; os pontos que ainda dependem de confirmação contra
o banco real seguem marcados com `-- TODO(confirmar)` (schema) ou `-- TODO(decisão)` (regra de
negócio) em `sql/audiencias_realizadas_v2_draft.sql`.

## 0. `id_tipo_audiencia` confirmados (pje.tb_tipo_audiencia)

O usuário rodou a query 4.1 e devolveu os 36 tipos cadastrados. Mapeamento para as categorias do
documento:

| Categoria (documento) | ids |
|---|---|
| Inicial | 3, 16 (sumaríssimo), 22 (videoconf), 29 (videoconf sumaríssimo) |
| UNA | 5, 19 (sumaríssimo), 23 (videoconf), 31 (videoconf sumaríssimo), **7 (RS ou Justificação Prévia), 9 (RS)** |
| Instrução | 6, 12 (sumaríssimo), 24 (videoconf), 27 (videoconf sumaríssimo) |
| Encerramento de Instrução | 10, 25 (videoconf) |
| Julgamento | 4 (confirma o que a query original já assumia) |

**Decidido pelo usuário:** tipos totalmente fora do documento (Conciliação em Conhecimento
(1, 32, 20, 33), Conciliação em Execução (2, 34, 36, 21, 35, 37), Inquirição de testemunha —
juízo deprecado (11, 26), Justificação Prévia (18), Mediação (13, 14, 15, 28), Pública (17, 30))
**ficam de fora** da população avaliada. Já implementado assim.

**Decidido pelo usuário:** ids `7` ("UNA-RS ou Justificação Prévia") e `9` ("Una - RS") entram
no grupo **UNA**, com base na hipótese de que "RS" = "Rito Sumário" (terceiro rito trabalhista,
distinto do sumaríssimo já mapeado). **Não confirmado contra o banco** — é uma inferência de
direito do trabalho, não uma verificação de dado; se "RS" significar outra coisa, ou o "ou
Justificação Prévia" do id `7` for relevante nalgum caso, revisar. Já aplicado no array
`tipo_una` da CTE `parametros`.

**Ainda pendente:**

- `8` Instrução e Julgamento — segue a árvore da Instrução (seção 2.4 — diligência+Encerramento
  de Instrução → Efetiva; sem diligência+Julgamento → Efetiva; regra geral de mesma categoria
  se redesignada; caso contrário Adiada por omissão), ou tem regra própria?

## 1. Resumo da lógica atual (query original)

A query original aplica **uma única regra genérica**, igual para todos os tipos de audiência
(exceto tipo 4, excluído da população avaliada — provavelmente "Julgamento"):

- `audiencias_realizadas`: audiências com `cd_status_audiencia = 'F'`, `id_tipo_audiencia <> 4`,
  processo com `cd_processo_status = 'D'`, dentro da janela de datas de referência.
- `audiencias_adiadas`: uma audiência é **ADIADA** quando, na janela de
  `data da audiência` até `data da audiência + 5 dias corridos`, **não existir**:
  - evento de processo com `ds_texto_final_externo ILIKE 'Conclusos%sentença%'`, **ou**
  - evento cujo `ds_caminho_completo ILIKE 'Magistrado|Julgamento%'`, **ou**
  - evento com `id_evento IN (941, 371)`, **ou**
  - uma nova audiência de tipo 4 (Julgamento) marcada nessa mesma janela.
- `audiencias_encerradas` = `audiencias_realizadas` − `audiencias_adiadas` → marcadas como
  **EFETIVA**.
- O filtro externo (`WHERE ... dt_fim <= current_date - 6`) só garante que a janela de 5 dias já
  tenha "fechado" antes de a audiência entrar no resultado.

Ou seja: hoje o sistema não sabe diferenciar Inicial, UNA e Instrução — aplica o mesmo teste
"houve sinal de sentença/julgamento em até 5 dias?" para todas.

## 2. Resumo das novas regras (documento SETIC)

O documento define uma **árvore de decisão por tipo de audiência**:

### 2.1 Regra geral (todos os tipos)
Se o magistrado **redesigna audiência da mesma categoria** da que acabou de ocorrer
(Inicial→Inicial, UNA→UNA, Instrução→Instrução) → **ADIADA**, sem janela de tempo definida.

> O documento é explícito (linha 12 do texto extraído): "Aplica-se a todos os tipos: Inicial,
> UNA (rito ordinário ou sumaríssimo) e Instrução." — ou seja, o escopo do documento inteiro
> (não só desta regra) é declarado como restrito a essas 3 famílias. Isso reforça (mas não
> resolve sozinho) a pergunta 3 da seção 0 sobre os tipos fora do documento.

### 2.2 Audiência Inicial
- Designação de **qualquer** audiência subsequente (UNA, Instrução, Encerramento de Instrução
  ou Julgamento) → **EFETIVA** ("cumpriu seu papel ao gerar encaminhamento processual").
- Designação de **nova** Inicial → **ADIADA** (regra geral, mesma categoria).

### 2.3 Audiência UNA (rito ordinário ou sumaríssimo)
- Nova UNA designada → **ADIADA** (regra geral).
- **Bipartição** (Instrução designada após a UNA) → **ADIADA por padrão**, com 3 exceções
  avaliadas em **até 3 dias úteis**:
  1. Há ao menos um movimento de diligência (perícia ativa, expedição de ofício, expedição de
     carta precatória, expedição de mandado) **e** Encerramento de Instrução é designado →
     **EFETIVA**.
  2. Não há diligências pendentes **e** há conclusão para sentença, prolação de sentença,
     homologação de acordo **ou** marcação de Audiência de Julgamento → **EFETIVA**.
  3. Nenhum movimento esperado ocorre e mesmo assim Instrução é designada → **ADIADA**
     ("bipartição injustificada").

### 2.4 Audiência de Instrução
- Nova Instrução designada → **ADIADA** (regra geral).
- Movimentos de diligência (perícia, ofício, carta precatória, mandado) em até 3 dias úteis
  **e** Encerramento de Instrução designado → **EFETIVA**.
- Sem diligências pendentes **e** Julgamento designado → **EFETIVA**.

### 2.5 Movimentos monitorados (UNA e Instrução)
1. **Perícia ativa** — perito designado e laudo em aberto (`status != finalizado`) **com prazo
   válido/não vencido**. Se o prazo estiver vencido, a regra muda para as do **painel de
   perícias do PAI** (fora do escopo desta query — dependência externa).
2. Expedição de ofício
3. Expedição de carta precatória
4. Expedição de mandado
5. Marcação de audiência de julgamento
6. Conclusão para sentença
7. Prolação de sentença
8. Homologação de acordo

## 3. Divergências identificadas (gap analysis)

| # | Divergência | Query atual | Regra nova | Impacto |
|---|---|---|---|---|
| 1 | **Sem diferenciação por tipo de audiência** | Uma regra única (`NOT EXISTS` de sentença/julgamento) para Inicial, UNA e Instrução | Árvore de decisão distinta por tipo | Estrutural — a query precisa ramificar por `tta.ds_tipo_audiencia`/`id_tipo_audiencia` |
| 2 | **Inicial: qualquer audiência subsequente conta como EFETIVA** | Só considera EFETIVA se houver sinal de sentença/julgamento ou nova audiência tipo 4 | Designar UNA **ou** Instrução **ou** Encerramento de Instrução já é suficiente | Inicial seguida de UNA/Instrução hoje é classificada (por padrão) como ADIADA — deveria ser EFETIVA |
| 3 | **"Encerramento de Instrução" nunca é verificado** | Não existe nenhuma referência a esse tipo de audiência na query | É sinal obrigatório na ramificação "diligência" de UNA e de Instrução | Precisa localizar o `id_tipo_audiencia` de "Encerramento de Instrução" |
| 4 | **Janela de tempo: 5 dias corridos vs. 3 dias úteis** | `dta_audiencia + INTERVAL '5' DAY` (corridos), aplicada uniformemente | UNA/Instrução: 3 dias **úteis**. Regra geral de mesma categoria e Inicial→subsequente: sem janela explícita no documento | Precisa de tabela de feriados/calendário útil para contar dias úteis; janela atual não bate com nenhuma das regras novas |
| 5 | **Catálogo de movimentos incompleto** | Só verifica `Conclusos...sentença`, caminho `Magistrado\|Julgamento%`, `id_evento IN (941,371)` e nova audiência tipo 4 | 8 movimentos distintos: perícia ativa (com condição de status/prazo), ofício, carta precatória, mandado, marcação de julgamento, conclusão p/ sentença, prolação de sentença, homologação de acordo | Faltam pelo menos: perícia ativa, ofício, carta precatória, mandado, homologação de acordo — precisam de `id_evento`/`ds_caminho_completo` próprios |
| 6 | **Redesignação de mesma categoria não é detectada diretamente** | A ADIADA é inferida por ausência de sinais de sentença/julgamento (efeito colateral, não regra explícita) | Regra geral explícita: nova audiência da mesma categoria = ADIADA, independente de outros sinais | Hoje "funciona por coincidência" em alguns casos, mas não é robusto (ex.: Inicial redesignada + também ocorre algo parecido com sentença simultaneamente — caso não tratado) |
| 7 | **Dependência externa "painel de perícias do PAI"** | Não existe | Perícia com prazo vencido segue outra régua, de outro indicador | Fora do escopo desta query — precisa decidir se é sinalizada como "depende de outro painel" ou tratada como não-diligência aqui |
| 8 | **`ds_classe_judicial` já é buscado mas não usado na decisão** | Join existe, mas classe não entra em nenhum `WHERE`/`EXISTS` | Documento cita "rito ordinário ou sumaríssimo" só como contexto do título da seção UNA, sem regra diferente por rito | Sem impacto direto — apenas confirmar que não há regra oculta por rito antes de assumir isso |

## 3.1 Atualizações (calendário de dias úteis e tabela de movimentos)

O usuário indicou duas tabelas que resolvem parte das divergências 4 e 5 da seção 3:

- **`pje.tb_calendario_eventos`** — tem `dt_dia`/`dt_mes`/`dt_ano`, `in_feriado`,
  `in_ativo`, `id_orgao_julgador`, `id_estado`, `id_municipio`, `in_abrangencia`,
  `in_suspende_prazo` e `in_suspende_audiencia`. Dá para calcular "N dias úteis a partir de uma
  data" em SQL puro (sem função nova), via `generate_series` + `NOT EXISTS` contra essa tabela —
  implementado na CTE `calendario_3du` do rascunho v2.
- **`pje.tb_evento_processual`** (`id_evento_processual = id_evento` de `pje.tb_evento`) — tem a
  coluna `ds_movimento`, provavelmente o nome do movimento padronizado (possivelmente a Tabela
  Processual Unificada do CNJ), mais confiável para casar texto do que `tb_evento.ds_evento`.
  Passou a ser a fonte principal de texto nas CTEs `movimentos_diligencia` e
  `movimentos_julgamento` do rascunho v2 (`sql/audiencias_realizadas_v2_draft.sql`).

**Decidido pelo usuário:**

- Dia útil = dia em que `in_suspende_prazo <> 'S'` **e** `in_suspende_audiencia <> 'S'` (ambos
  precisam estar livres). Implementado na CTE `calendario_3du` com
  `(ce.in_suspende_prazo = 'S' OR ce.in_suspende_audiencia = 'S')` dentro do `NOT EXISTS`.
- Abrangência: nacional (`id_orgao_julgador IS NULL`/`id_estado IS NULL`) **ou** estado de São
  Paulo (`id_estado = 26`). `id_municipio` segue sem tratamento — **dúvida de negócio em aberto,
  levada ao chamado da SETIC**: se um registro do calendário suspender audiência/prazo só num
  município específico (não no estado inteiro), esse dia deve contar como não-útil apenas para
  as varas daquele município, ou nacional+estadual já é suficiente?

Ainda **não confirmado**:

- Se "Marcação de audiência de julgamento" deve ser detectada como movimento ou apenas como
  novo registro em `tb_processo_audiencia` com `id_tipo_audiencia` = Julgamento (o rascunho hoje
  usa a segunda via, igual à query original).
- Se existe tabela de complemento/parâmetro estruturada para "tipo de documento" expedido
  (mais robusta que `ILIKE` em texto livre — ver seção 3.2).

## 3.3 Perícia ativa — resolvido (`tb_processo_pericia`)

O usuário forneceu a query do **painel de perícias do PAI** (`sql/painel_pericias_referencia.sql`),
usada como fonte da condição "perícia ativa": `tb_processo_pericia` (status `L`/`S`/`A`/`M` =
laudo em aberto, não finalizado) + `tb_proc_parte_expediente.dt_prazo_legal_parte` (prazo de
entrega) + `tb_processo_expediente.ds_origem_expediente = 'PERICIA'` + `tb_pess_doc_identificacao.
in_principal = 'S'` (perito principal).

Implementado na CTE `movimentos_diligencia` (segundo `SELECT` do `UNION`, em
`sql/audiencias_realizadas_v2_draft.sql`): perícia com status aberto **e**
`dt_prazo_legal_parte >= CURRENT_DATE` (prazo válido) conta como diligência. Prazo vencido segue
fora de escopo (regras do próprio painel de perícias, ponto 5 do cabeçalho do rascunho).

**Decidido pelo usuário:** referência de "prazo válido" = `CURRENT_DATE - 1 dia`, igual à "Data
de referência do relatório" do painel de perícias original. Implementado em
`movimentos_diligencia` (`ppex.dt_prazo_legal_parte >= CURRENT_DATE - INTERVAL '1 day'`).

**Ainda não confirmado:**
- Se a janela de 3 dias úteis deve se aplicar à data de marcação da perícia (`pp.dt_marcacao`),
  como para os demais movimentos, ou se "perícia ativa" deve contar independente de quando foi
  marcada (já que é um estado contínuo, não um ato pontual como expedir um documento).

## 3.4 Correções de implementação encontradas numa releitura linha a linha do documento

Uma releitura cuidadosa do texto extraído do documento (comparando frase a frase com o rascunho
v2) encontrou **3 bugs de implementação** — não são dúvidas de negócio, o próprio texto do
documento já responde, o rascunho é que modelava errado — e **2 lacunas no documento** que essas
não são bug nenhum, é o texto que simplesmente não cobre o caso.

**Bugs corrigidos:**

a. **"Mesma categoria redesignada" comparava id exato, não categoria.** O rascunho anterior
   comparava `pa.id_tipo_audiencia_proxima = r.id_tipo_audiencia` (id exato). Como cada categoria
   tem 4 variantes (presencial/videoconferência × ordinário/sumaríssimo — ver seção 0), uma UNA
   presencial seguida de uma UNA por videoconferência (ids diferentes, mesma categoria) não era
   detectada como "mesma categoria redesignada". Corrigido para comparar por grupo (os arrays de
   `parametros`).
b. **"Encerramento de Instrução designado" nunca era exigido de fato.** O rascunho anterior só
   checava se havia diligência (perícia/ofício/carta/mandado) para marcar Efetiva nos ramos de
   bipartição da UNA e da Instrução, mas a linha do documento "A designação de Encerramento de
   Instrução é **obrigatória** quando há diligências pendentes" deixa claro que os dois sinais
   são exigidos **juntos**. Corrigido com a nova CTE `encerramento_instrucao_na_janela`.
c. **"Marcação de audiência de julgamento" só olhava a audiência imediatamente seguinte.** O
   rascunho anterior usava `proxima_audiencia` (a única audiência seguinte, via `LIMIT 1`) para
   checar esse sinal. Mas na bipartição UNA→Instrução, a Instrução já ocupa o lugar de "próxima
   audiência" — o Julgamento (ou o Encerramento de Instrução, item b) viria depois dela, não é "a
   próxima" em relação à UNA original. Esse sinal nunca seria detectado nesses casos. Corrigido
   com a nova CTE `audiencias_subsequentes`, que lista **todas** as audiências futuras do
   processo, não só a primeira.

**Lacunas do próprio documento (não são bug, precisam de decisão — itens novos na lista de
dúvidas para a SETIC, seção 5):**

d. O documento cobre só dois desfechos para a UNA: "designa nova UNA" e "designa Instrução
   (bipartição)". O que acontece se a UNA é seguida de um tipo que **não é nenhum dos dois** —
   por exemplo, Encerramento de Instrução ou Julgamento designados diretamente, pulando a
   Instrução? Hoje cai em Adiada por omissão (último `ELSE` do `CASE`).
e. Para a Instrução (seção 2.4), a UNA tem um rótulo explícito para o caso "nada aconteceu"
   ("bipartição injustificada" → Adiada), mas a Instrução não tem um equivalente escrito. Qual o
   status quando **nem** "diligência + Encerramento de Instrução" **nem** "sem diligência +
   Julgamento" se aplicam? Hoje também cai em Adiada por omissão, por analogia com a UNA — mas
   isso é uma suposição minha, não algo que o texto diga.

## 3.2 Códigos de movimento confirmados (amostra de `tb_evento_processual`)

O usuário devolveu uma amostra grande de `tb_evento_processual (id_evento_processual, cd_evento,
ds_movimento)`. Como `ds_movimento` é o texto de **catálogo** e mantém os placeholders
(`#{tipo de documento}`, `#{nome da parte}` etc.), a forma robusta de identificar cada movimento
passou a ser o código numérico (`tpe.id_evento`, que corresponde a `id_evento_processual`), e não
mais `ILIKE` no catálogo:

| Movimento (documento) | Código(s) confirmados | Observação |
|---|---|---|
| Conclusão para sentença | `51` | "Conclusos os autos para #{tipo de conclusão}..." — mesma lógica da query original: `ds_texto_final_externo ILIKE '%sentença%'` sobre o texto **resolvido**, já que o tipo de conclusão é parâmetro |
| Prolação de sentença | `219, 220, 221, 50110, 50118` | Não existe um movimento literal "Prolação de sentença"; o julgamento de mérito em 1º grau aparece como resultado específico (procedente/improcedente/procedente em parte/julgado antecipadamente/liminarmente improcedente) |
| Homologação de acordo | `466` | Não existe texto literal "Homologação de acordo"; o termo técnico trabalhista é "transação" — `466 Homologada a transação (Valor da transação: ...)` |
| Expedição de ofício / carta precatória / mandado | `60` (mesmo código para os três) | "Expedido(a) #{tipo de documento} a(o) #{destinatário}" — os três tipos são a MESMA movimentação genérica; só dá pra diferenciar pelo texto resolvido (`ds_texto_final_externo ILIKE '%Ofício%'` / `'%Carta Precatória%'` / `'%Mandado%'`) |
| Perícia ativa | — | Nenhum movimento correspondente na amostra de `tb_evento_processual` — resolvido por outra via, ver seção 3.3 (`tb_processo_pericia`) |

**Achado extra, sobre a query ORIGINAL (não o rascunho):** os ids `941` e `371`, usados nela
como sinal adicional de "Efetiva" (`OR e.id_evento IN (941, 371)`), correspondem — pela mesma
amostra — a `941 = "Declarada a incompetência"` e `371 = "Acolhida a exceção de incompetência"`.
Não têm relação direta com sentença/julgamento.

**Decidido pelo usuário: "mantém".** Reproduzido na v2 com prioridade máxima no `CASE` de
classificação (CTE `incompetencia_na_janela`), igual à query original — se um desses dois
eventos ocorre dentro da janela, a audiência é Efetiva independentemente de qualquer outra
condição (inclusive redesignação de mesma categoria), reproduzindo o comportamento original em
que esse sinal vivia dentro do mesmo bloco que decidia Adiada. Ajuste assumido (não pedido
explicitamente): usa a janela de 3 dias úteis da v2, não os 5 dias corridos da query original —
sinalizar se isso não for o esperado.

**Confirmação cruzada via `pje.tb_evento` (id_evento, ds_evento — rótulo curto/categoria, o
usuário devolveu essa tabela também):** bate com tudo acima —
`60 = "Expedição de documento"`, `51 = "Conclusão"`, `219/220/221 = "Procedência"/
"Improcedência"/"Procedência em parte"`, `466 = "Homologação de transação"`,
`941/371/374 = "Incompetência"` (reforça o achado acima), `970 = "Audiência"` (confirma que é
genérico demais para servir de sinal de "marcação de julgamento" — por isso o rascunho continua
detectando isso via novo registro em `tb_processo_audiencia`, não via movimento). Perícia
continua sem nenhuma entrada, nem em nível de categoria.

**Pendência nova — sentença terminativa:** `tb_evento` também mostra categorias de sentença que
**não resolve o mérito** (extinção do processo): `456 Extinção` e subcausas (`458` abandono da
causa, `459` ausência de pressupostos processuais, `461` ausência das condições da ação, `463`
desistência, `464` ação intransmissível, `465` confusão entre autor e réu), `454` indeferimento
da petição inicial, e `50126 Julgamento antecipado parcial (SEM resolução do mérito)`. Uma
sentença terminativa também encerra a fase de conhecimento, então pode se qualificar como
"Prolação de sentença" tanto quanto uma sentença de mérito — hoje o rascunho só considera as de
mérito (219/220/221/50110/50118). **Perguntei ao usuário; a resposta foi "preciso confirmar com
a SETIC"** — os códigos terminativos ficam comentados (não ativos) em
`movimentos_julgamento`, prontos para descomentar quando a decisão vier.

## 4. Queries de descoberta (rodar contra `pje_1grau_cds` quando houver acesso)

```sql
-- 4.1 Tipos de audiência existentes (RESPOSTA à pergunta "em qual tabela encontro os
-- ids dos tipos de audiência?" — é a mesma tabela já usada na query original, alias `tta`)
-- Localiza os ids de Inicial, UNA, Instrução, Encerramento de Instrução, Julgamento.
SELECT id_tipo_audiencia, ds_tipo_audiencia
FROM pje.tb_tipo_audiencia
ORDER BY 1;

-- 4.2 [RESOLVIDA] Códigos de movimento confirmados via amostra de tb_evento_processual — ver
-- tabela na seção 3.2. Query mantida aqui só para conferência pontual de um código específico:
SELECT id_evento_processual, cd_evento, ds_movimento
FROM pje.tb_evento_processual
WHERE id_evento_processual IN (51, 60, 219, 220, 221, 466, 941, 371, 50110, 50118);

-- 4.2.2 Localizar tabela de complemento que guarde o "tipo de documento" expedido de forma
-- estruturada (ofício/carta precatória/mandado), como alternativa ao ILIKE em texto livre
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'pje'
  AND table_name ILIKE '%processo_evento%'
  AND (column_name ILIKE '%tipo%doc%' OR column_name ILIKE '%complement%');

-- 4.2.1 Amostra de tb_calendario_eventos para entender os flags de dia útil/feriado
-- (in_feriado x in_suspende_prazo x in_suspende_audiencia) e o alcance de
-- id_orgao_julgador/id_estado/id_municipio/in_abrangencia
SELECT *
FROM pje.tb_calendario_eventos
WHERE in_ativo = 'S'
  AND dt_ano = EXTRACT(YEAR FROM CURRENT_DATE)
ORDER BY dt_mes, dt_dia
LIMIT 100;

-- 4.3 [RESOLVIDA pela query 4.2] ids 941/371 da query original = "Declarada a incompetência" /
-- "Acolhida a exceção de incompetência" — ver achado extra na seção 3.2.

-- 4.4 [RESOLVIDA] Controle de perícia = tb_processo_pericia + tb_proc_parte_expediente +
-- tb_processo_expediente — ver seção 3.3 e sql/painel_pericias_referencia.sql.

-- 4.5 Validação da regra de dia útil já decidida (in_suspende_prazo OU in_suspende_audiencia,
-- abrangência nacional ou SP/26) — conferir se a contagem de dias não-úteis por ano é plausível
SELECT dt_ano, COUNT(*) AS dias_nao_uteis
FROM pje.tb_calendario_eventos
WHERE in_ativo = 'S'
  AND (in_suspende_prazo = 'S' OR in_suspende_audiencia = 'S')
  AND (id_orgao_julgador IS NULL OR id_estado IS NULL OR id_estado = 26)
GROUP BY dt_ano
ORDER BY dt_ano;
```

## 5. Próximos passos sugeridos

**Resolvido:**
1. ~~Definir como calcular "3 dias úteis"~~ — `tb_calendario_eventos` + `generate_series`,
   implementado na CTE `calendario_3du`. Regra: dia útil = `in_suspende_prazo <> 'S'` e
   `in_suspende_audiencia <> 'S'`; abrangência nacional ou estado de SP (`id_estado = 26`).
2. ~~`id_tipo_audiencia` de Inicial/UNA/Instrução/Encerramento de Instrução/Julgamento~~ — ver
   seção 0, aplicados na CTE `parametros`.
3. ~~Códigos dos 8 movimentos monitorados~~ — ver seção 3.2, aplicados nas CTEs
   `movimentos_diligencia`/`movimentos_julgamento`.
3.1 ~~Localizar fonte de "perícia ativa"~~ — ver seção 3.3, `tb_processo_pericia` + query do
   painel de perícias do PAI, aplicada na CTE `movimentos_diligencia`.
3.2 ~~3 bugs de implementação encontrados numa releitura linha a linha do documento~~ — ver
   seção 3.4: (a) "mesma categoria" comparava id exato em vez de grupo; (b) "Encerramento de
   Instrução designado" nunca era exigido junto com a diligência; (c) "marcação de audiência de
   julgamento" só olhava a audiência imediatamente seguinte. Todos corrigidos no rascunho v2.
3.3 ~~Tipos fora do documento~~ — decidido: ficam de fora da população avaliada (seção 0), já
   implementado.
3.4 ~~ids `941`/`371` da query original~~ — decidido: "mantém". Reproduzido na v2 com prioridade
   máxima (CTE `incompetencia_na_janela`), ver seção 3.2.
3.5 ~~Janela de 3 dias úteis aplicada só onde o documento determina~~ — decidido: Regra Geral e
   Inicial não têm janela; já implementado assim (nenhuma mudança necessária).
3.6 ~~`7`/`9` "...RS"~~ — decidido: entram no grupo UNA (hipótese "Rito Sumário", não confirmada
   contra o banco), já aplicado no array `tipo_una`.

**Ainda pendente:**
4. `8` "Instrução e Julgamento" — segue a árvore da Instrução (detalhada na conversa) ou tem
   regra própria?
4.2 Duas lacunas do próprio documento, achadas na releitura (seção 3.4, itens d/e): o que
   acontece com UNA seguida de um tipo que não é UNA nem Instrução; e qual o status da Instrução
   quando nem diligência+Encerramento nem sem-diligência+Julgamento se aplicam.
5. Confirmar com a SETIC se "Prolação de sentença" deve incluir sentença terminativa (extinção
   sem resolução do mérito — códigos 456/458/459/461/463/464/465/454/50126), hoje comentados
   em `movimentos_julgamento` no rascunho (ver seção 3.2).
6. Rodar a query 4.5 para validar a regra de dia útil contra a contagem real de dias não-úteis
   por ano.
7. Decidir se a janela de 3 dias úteis se aplica à marcação da perícia (`pp.dt_marcacao`) (ver
   seção 3.3; a referência de prazo válido já foi decidida: `CURRENT_DATE - 1 dia`).
7.1 Confirmar com a SETIC a abrangência municipal (`id_municipio`) da regra de dia útil — hoje
   só cobre nacional + estado de SP (ver seção 3.1).
8. Rodar a query 4.2.2 para checar se existe uma tabela de complemento estruturada para "tipo de
   documento" expedido (alternativa mais robusta ao `ILIKE` em `ds_texto_final_externo` usado
   hoje para diferenciar ofício/carta precatória/mandado, todos sob o código `60`).
9. Com os pontos acima resolvidos, finalizar `sql/audiencias_realizadas_v2_draft.sql`
   substituindo os `-- TODO(confirmar)`/`-- TODO(decisão)` restantes e testar contra casos
   reais conhecidos (audiências já classificadas manualmente, se houver).

## 6. Tabela de monitoramento final (à luz da proposta "Governança da Decisão" v8)

A proposta exige que o dado do painel seja **validado** (Etapa 3), **rastreável** (Etapa 4, trilha
encadeada por hash) e **explicável na origem** (Etapa 5), com registro **por unidade, nunca por
pessoa**. Isso pede duas tabelas separadas — a trilha não guarda conteúdo processado, só o
registro técnico da execução:

### 6.1 `fato_audiencia_classificada` — o que o PAI consome (uma linha por audiência e versão de regra)

| Grupo | Coluna | Tipo | Por quê |
|---|---|---|---|
| Chave | `id_processo_audiencia` | bigint | Chave natural na origem; com `versao_regra`, forma a PK (permite upsert/reprocessamento) |
| Chave | `versao_regra` | varchar | Qual regra classificou (ex. `ORIGINAL`, `SETIC-v2`). Permite rodar as duas em paralelo e comparar antes de virar a chave |
| Identificação | `id_processo`, `nr_processo` | | Já existentes |
| Identificação | `id_orgao_julgador` | int | Unidade — granularidade de registro exigida pela proposta |
| Identificação | `dt_audiencia` | timestamp | Já existente |
| Identificação | `id_tipo_audiencia` | int | Hoje só sai o texto; o id é o que as regras usam |
| Identificação | `tipo_audiencia` | varchar | Já existente (sem "por videoconferência") |
| Identificação | `categoria_audiencia` | varchar | `Inicial`/`UNA`/`Instrução` — a unidade das regras novas |
| Identificação | `rito` | varchar | `Ordinário`/`Sumário`/`Sumaríssimo` — explicita o mapeamento RS |
| Identificação | `modalidade`, `ds_classe_judicial`, `fase` | | Já existentes |
| Resultado | `status` | varchar | `Efetiva`/`Adiada` |
| Resultado | `regra_aplicada` | varchar | Código do ramo que decidiu (ex. `R0_INCOMPETENCIA`, `R1_MESMA_CATEGORIA`, `R3C_BIPARTICAO_INJUSTIFICADA`, `R9_OMISSAO`). É o que torna a classificação verificável, e mede quantos casos caem nas lacunas do documento |
| Evidência | `id_tipo_audiencia_proxima`, `dt_marcacao_proxima` | | Sinal da regra geral/Inicial/bipartição |
| Evidência | `fl_diligencia`, `tp_diligencia` | bool, varchar | Ofício/Carta/Mandado/Perícia |
| Evidência | `fl_encerramento_instrucao`, `fl_julgamento_designado` | bool | |
| Evidência | `fl_conclusao_sentenca`, `fl_sentenca`, `fl_homologacao_acordo`, `fl_incompetencia` | bool | |
| Evidência | `dt_limite_janela` | date | 3º dia útil calculado — auditável contra o calendário |
| Linhagem | `id_execucao` | bigint | FK para a trilha (6.2) — liga cada linha à carga que a produziu |
| Linhagem | `dt_referencia` | date | Data de apuração (tipo `date`, não texto). Necessária porque "perícia ativa" depende da data em que se roda |
| Linhagem | `fonte` | varchar | `pje_1grau_cds` |

**Sair ou rever:**
- `magistrado` (nome) — conflita com o princípio da proposta ("não há métrica individual de
  magistrado ou de servidor"). Com essa coluna o painel permite ranquear efetividade por juiz.
  Decisão do usuário.
- `dt_ult_mov` — sempre `NULL` na original e na v2. Provavelmente existe só para casar com o
  `UNION` da pauta programada (DW_TRT). Se for isso, manter; senão, remover.
- `dta_ref` — hoje é texto (`TO_CHAR`); substituir por `dt_referencia` do tipo `date`.

### 6.2 `trilha_execucao` — monitoramento da carga (Etapas 3 e 4; "Log do Placar" do mockup)

| Coluna | Uso |
|---|---|
| `id_execucao` | PK |
| `etapa` | Extração / Classificação / Carga |
| `versao_regra` | Qual regra rodou |
| `parametro_ult_dt` | Valor de `VAR_ULT_DT_AUDIENCIA` usado — reprodutibilidade |
| `dt_inicio`, `dt_fim`, `duracao_seg` | Base do indicador "Tempo Médio de Recuperação" |
| `status` | Sucesso / Falha / Alerta |
| `linhas_lidas`, `linhas_gravadas`, `linhas_retidas_janela_aberta` | Validação de volume |
| `qtd_efetiva`, `qtd_adiada`, `qtd_regra_omissao` | Placar; desvio contra a média histórica vira alerta |
| `pct_desvio_volume` | Desvio contra as últimas N execuções |
| `id_execucao_reprocessada` | Liga a reexecução à falha — permite medir o tempo de recuperação |
| `fl_intervencao_humana`, `unidade_intervencao`, `motivo_intervencao` | Exigidos pela proposta; unidade, não pessoa |
| `hash_log`, `hash_anterior` | Encadeamento — alterar um registro rompe a cadeia |

Validações sugeridas para `status = Alerta`: volume fora de ±X% da média; `qtd_regra_omissao`
acima de um limiar; qualquer `dt_limite_janela` nulo; proporção Efetiva/Adiada fora da faixa
histórica.

## 7. Reavaliação completa (após a proposta v8)

**Corrigido nesta revisão (bugs técnicos):**
1. O calendário só bloqueava o **dia inicial** de cada evento — `tb_calendario_eventos` tem
   `dt_dia_final`/`dt_mes_final`/`dt_ano_final` para períodos (recesso 20/12–20/01). Agora bloqueia o
   intervalo.
2. A busca de dias úteis ia só até +15 dias — insuficiente no recesso (limite vinha `NULL`, a
   audiência virava Adiada por falta de sinais). Agora +60 dias, e limite `NULL` não é
   classificado.
3. O buffer fixo de 10 dias classificava audiências antes de a janela fechar (ex.: audiência em
   19/12, janela fecha ~23/01). Agora só classifica quando `dt_limite_janela < CURRENT_DATE`.
4. `in_ativo`/`in_suspende_prazo` são do domínio `pje."boleano"`; comparar com `'S'` quebra se
   o tipo base for boolean. Comparação feita via `::text`, que funciona nos dois casos.

**Achados que precisam de decisão:**
5. **Crítico — UNA/Inicial sem audiência subsequente viram Adiada.** Todos os ramos da UNA exigem
   que a próxima audiência seja Instrução; a Inicial exige alguma próxima audiência. Uma UNA que
   termina com sentença ou acordo (o melhor desfecho possível) ou uma Inicial com acordo
   homologado não têm próxima audiência e caem no `ELSE 'Adiada'`. A query original classificava
   esses casos como Efetiva. É uma regressão da v2 — ver pergunta 1 da lista em 7.1.
6. **A query original já tratava sentença terminativa como efetiva.** O filtro
   `ds_caminho_completo ILIKE 'Magistrado|Julgamento%'` cobre toda a subárvore Julgamento da TPU
   — mérito (219/220/221), terminativas (456–465, 454), arquivamento por ausência do reclamante
   (473), homologação de transação (466). Os ids 941/371 foram somados à parte justamente por
   ficarem fora dessa subárvore (Magistrado > Decisão > Declaração). Evidência forte para a
   pergunta de sentença terminativa.
7. **"Perícia ativa" é avaliada no estado atual, não no da janela.** `cd_status_pericia` e
   `id_proc_parte_exp_ultimo` são o estado de hoje: uma perícia marcada na janela com laudo já
   entregue na data da carga deixa de contar e pode virar Adiada. Reprocessar mais tarde muda o
   resultado — por isso `dt_referencia` na tabela.
8. **"Inicial → qualquer subsequente"** hoje aceita qualquer tipo (inclusive Conciliação,
   Mediação); o documento lista quatro (UNA, Instrução, Encerramento, Julgamento).
9. **Audiências canceladas** entram em `audiencias_subsequentes` (não há filtro por
   `cd_status_audiencia`). A original também não filtrava.

## 7.0 `VAR_ULT_DT_AUDIENCIA` é autorreferente (confirmado pelo usuário)

O usuário confirmou a origem da variável:

```sql
-- maior data de audiência excluindo as programadas
SELECT MAX(dt_audiencia) AS ultima_dt
FROM pai_2_0.audiencias
WHERE status <> 'Programada'
```

Ou seja, o watermark é lido **da própria tabela de destino** (`pai_2_0.audiencias`) que a carga
grava — não é um parâmetro externo independente. Isso confirma, na prática, o risco já
sinalizado como `TODO(confirmar)` na query (linha ~166 de
`sql/audiencias_realizadas_v2_draft.sql`):

- Como o limite de 3 dias úteis varia por vara/calendário local, duas audiências do **mesmo dia**
  podem ter suas janelas fechando em datas diferentes.
- Assim que **qualquer** audiência com `dt_audiencia` de um certo dia (ou posterior) for gravada
  em `pai_2_0.audiencias`, o `MAX(dt_audiencia)` avança e o filtro `dt_inicio > ultima_dt`
  **exclui permanentemente** qualquer outra audiência daquele mesmo dia (ou de dias anteriores a
  esse máximo) que ainda não tenha sido processada — mesmo que sua janela de 3 dias úteis só
  feche depois.
- Não há reprocessamento: uma vez que o `MAX` passa por uma data, ela nunca mais entra no filtro
  `>`.

**Consequência prática:** carga com esse padrão de watermark autorreferente tende a **perder
audiências silenciosamente** (não gera erro, só nunca aparecem no resultado), especialmente perto
de janelas divergentes entre varas (recesso forense afeta comarcas/varas de forma não uniforme).

**Recomendação já registrada na query:** trocar o corte exato por uma **sobra de segurança** (ex.:
`MAX(dt_audiencia) - 45 dias`, não o valor exato do `MAX`) combinada com **upsert** na chave
`(id_processo_audiencia, versao_regra)` — assim reprocessar um período que já tem linhas
gravadas apenas atualiza (não duplica), e audiências "esquecidas" voltam a ser avaliadas a cada
carga. Ver tabela de monitoramento (seção 6.2, coluna `parametro_ult_dt` — guardar o valor usado
em cada execução também ajuda a auditar esse tipo de perda).

### 7.1 Lista consolidada para o chamado (substitui as anteriores)

1. **UNA e Inicial sem nova audiência** — UNA sem redesignação e sem bipartição, mas com sentença
   ou acordo; Inicial com acordo homologado ou arquivamento — são Efetivas? (A original as marcava
   Efetivas; a v2, pela letra do documento, as marca Adiadas.)
2. **UNA seguida de tipo que não é UNA nem Instrução** (Encerramento ou Julgamento direto).
3. **Instrução sem diligência e sem Julgamento designado** — Adiada por analogia com a UNA?
4. **Tipo 8 "Instrução e Julgamento"** — segue a árvore da Instrução ou regra própria?
5. **Sentença terminativa** conta como "prolação de sentença"? (A original contava — item 6.)
6. **Perícia ativa: avaliada em que momento?** No fim da janela de 3 dias úteis (determinístico)
   ou na data de apuração (como hoje)? E precisa ter sido marcada dentro da janela?
7. **"Qualquer audiência subsequente" da Inicial** — só os quatro tipos listados ou qualquer tipo?
8. **Dias úteis — abrangência municipal** entra no cálculo?
9. *(informativo)* ids 7/9 "RS" foram tratados como Rito Sumário (UNA) por inferência — confirmar.

**Decisões internas (não são para a SETIC):** manter ou retirar `magistrado`; manter
`dt_ult_mov` só se o UNION da pauta programada exigir; adotar o reprocessamento com sobra + upsert.
