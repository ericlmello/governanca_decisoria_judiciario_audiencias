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
| UNA | 5, 19 (sumaríssimo), 23 (videoconf), 31 (videoconf sumaríssimo) |
| Instrução | 6, 12 (sumaríssimo), 24 (videoconf), 27 (videoconf sumaríssimo) |
| Encerramento de Instrução | 10, 25 (videoconf) |
| Julgamento | 4 (confirma o que a query original já assumia) |

**Ambíguos/fora do documento — decisão do usuário pendente:**

- `8` Instrução e Julgamento — variante de Instrução, ou regra própria (sempre Efetiva, já que
  não depende de sinal posterior)?
- `7` UNA-RS ou Justificação Prévia / `9` Una - RS — o que significa "RS"? Variante de UNA ou
  outra coisa?
- Totalmente fora do documento (não aparecem em nenhuma seção da árvore de decisão):
  Conciliação em Conhecimento (1, 32, 20, 33), Conciliação em Execução (2, 34, 36, 21, 35, 37),
  Inquirição de testemunha — juízo deprecado (11, 26), Justificação Prévia (18), Mediação
  (13, 14, 15, 28), Pública (17, 30). Ficam fora da população avaliada em
  `sql/audiencias_realizadas_v2_draft.sql` até o usuário decidir se entram e com qual regra.

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
  Paulo (`id_estado = 26`). `id_municipio` segue sem tratamento — se algum feriado municipal for
  relevante para alguma vara específica, precisa ser adicionado depois.

Ainda **não confirmado**:

- Se "Marcação de audiência de julgamento" deve ser detectada como movimento ou apenas como
  novo registro em `tb_processo_audiencia` com `id_tipo_audiencia` = Julgamento (o rascunho hoje
  usa a segunda via, igual à query original).
- Se existe tabela de complemento/parâmetro estruturada para "tipo de documento" expedido
  (mais robusta que `ILIKE` em texto livre — ver seção 3.2).
- A tabela de perito/laudo para a condição de "perícia ativa" (query 4.4, ainda não rodada).

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
| Perícia ativa | — | Nenhum movimento correspondente na amostra. Confirma que depende de tabela de perito/laudo à parte, ainda não localizada |

**Achado extra, sobre a query ORIGINAL (não o rascunho):** os ids `941` e `371`, usados nela
como sinal adicional de "Efetiva" (`OR e.id_evento IN (941, 371)`), correspondem — pela mesma
amostra — a `941 = "Declarada a incompetência"` e `371 = "Acolhida a exceção de incompetência"`.
Não têm relação direta com sentença/julgamento. Pode ser intencional (processo resolvido/
remetido por incompetência também conta como audiência que cumpriu seu papel), mas **vale
confirmar com a SETIC** antes de decidir se esse sinal é replicado na v2 — por ora, o rascunho
não o inclui.

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

-- 4.4 Verificar se existe controle de perícia (perito/laudo) e onde fica o status/prazo
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'pje'
  AND (table_name ILIKE '%pericia%' OR table_name ILIKE '%perito%' OR table_name ILIKE '%laudo%');

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

**Ainda pendente:**
4. Decidir os itens ambíguos/fora do documento (seção 0): tipo `8` "Instrução e Julgamento";
   tipos `7`/`9` "...RS"; e o bloco Conciliação/Mediação/Pública/Inquirição/Justificação Prévia
   — hoje fora da população avaliada.
5. Confirmar com a SETIC se os ids `941`/`371` da query **original** (achado da seção 3.2) devem
   ser replicados na v2 como sinal de efetividade.
6. Rodar a query 4.5 para validar a regra de dia útil contra a contagem real de dias não-úteis
   por ano.
7. Localizar a tabela de perito/laudo para a condição de "perícia ativa" (query 4.4) e decidir o
   tratamento de perícia com prazo vencido (painel de perícias do PAI, fora de escopo, ou
   replicado aqui).
8. Rodar a query 4.2.2 para checar se existe uma tabela de complemento estruturada para "tipo de
   documento" expedido (alternativa mais robusta ao `ILIKE` em `ds_texto_final_externo` usado
   hoje para diferenciar ofício/carta precatória/mandado, todos sob o código `60`).
9. Com os pontos acima resolvidos, finalizar `sql/audiencias_realizadas_v2_draft.sql`
   substituindo os `-- TODO(confirmar)`/`-- TODO(decisão)` restantes e testar contra casos
   reais conhecidos (audiências já classificadas manualmente, se houver).
