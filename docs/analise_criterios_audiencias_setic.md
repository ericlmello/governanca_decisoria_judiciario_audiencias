# Análise: Query atual x Novos Critérios SETIC (PAI — Audiências)

Documento de referência: *PAI - Critérios Audiências SETIC.docx* (Critérios de Classificação de
Audiências — Definição de Efetivas/Adiadas e impactos no IAD).

> A coluna "Observação (Fora do script)" do documento foi ignorada, conforme solicitado, por
> se basear em movimentos manuais do PJe que não fazem parte da regra de negócio a implementar.

**Importante:** não foi possível conectar à base `10.2.36.13:3032` (`pje_1grau_cds`) a partir
deste ambiente — é um IP privado (RFC1918), inacessível a partir do container isolado na nuvem
usado nesta sessão (sem VPN/rota para a rede interna do TRT). Por isso, os `id_tipo_audiencia`,
`id_evento` e demais valores de referência citados abaixo **não puderam ser confirmados contra
o banco real**. A seção 4 traz as queries de descoberta prontas para rodar assim que houver
acesso, e a query revisada (seção 5) marca com `-- TODO(confirmar)` todo ponto que depende
dessa confirmação.

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

- Textos reais de `ds_movimento` para cada um dos 8 movimentos monitorados (seção 2.5) —
  a query 4.2 abaixo foi adaptada para `tb_evento_processual`, mas os padrões `ILIKE` ainda são
  chute por convenção de nomenclatura, não confirmados.
- Se "Marcação de audiência de julgamento" deve ser detectada como movimento em
  `tb_evento_processual` ou apenas como novo registro em `tb_processo_audiencia` com
  `id_tipo_audiencia` = Julgamento (o rascunho hoje usa a segunda via, igual à query original).

## 4. Queries de descoberta (rodar contra `pje_1grau_cds` quando houver acesso)

```sql
-- 4.1 Tipos de audiência existentes (RESPOSTA à pergunta "em qual tabela encontro os
-- ids dos tipos de audiência?" — é a mesma tabela já usada na query original, alias `tta`)
-- Localiza os ids de Inicial, UNA, Instrução, Encerramento de Instrução, Julgamento.
SELECT id_tipo_audiencia, ds_tipo_audiencia
FROM pje.tb_tipo_audiencia
ORDER BY 1;

-- 4.2 Movimentos candidatos aos "movimentos monitorados" (ajustar termos de busca)
-- Usa tb_evento_processual.ds_movimento (indicado pelo usuário como fonte mais confiável
-- que tb_evento.ds_evento), cruzando com tb_evento só para trazer o id_evento/caminho.
SELECT e.id_evento, e.ds_evento, e.ds_caminho_completo, ep.ds_movimento
FROM pje.tb_evento e
INNER JOIN pje.tb_evento_processual ep ON ep.id_evento_processual = e.id_evento
WHERE ep.ds_movimento ILIKE ANY (ARRAY[
    '%perícia%', '%pericia%', '%ofício%', '%oficio%', '%carta precatória%',
    '%carta precatoria%', '%mandado%', '%conclus%sentença%', '%conclus%sentenca%',
    '%prolação%sentença%', '%prolacao%sentenca%', '%homologa%acordo%'
])
ORDER BY ep.ds_movimento;

-- 4.2.1 Amostra de tb_calendario_eventos para entender os flags de dia útil/feriado
-- (in_feriado x in_suspende_prazo x in_suspende_audiencia) e o alcance de
-- id_orgao_julgador/id_estado/id_municipio/in_abrangencia
SELECT *
FROM pje.tb_calendario_eventos
WHERE in_ativo = 'S'
  AND dt_ano = EXTRACT(YEAR FROM CURRENT_DATE)
ORDER BY dt_mes, dt_dia
LIMIT 100;

-- 4.3 Confirmar os ids já usados na query original (941, 371)
SELECT id_evento, ds_evento, ds_caminho_completo
FROM pje.tb_evento
WHERE id_evento IN (941, 371);

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

1. ~~Definir como calcular "3 dias úteis"~~ — **resolvido**: `tb_calendario_eventos` +
   `generate_series`, implementado na CTE `calendario_3du` do rascunho v2. Regra: dia útil =
   `in_suspende_prazo <> 'S'` e `in_suspende_audiencia <> 'S'`; abrangência nacional ou
   estado de SP (`id_estado = 26`). Falta rodar a query 4.5 pra validar o resultado contra
   casos reais conhecidos.
2. Rodar a query 4.1 e devolver o resultado para eu confirmar os `id_tipo_audiencia` de
   Inicial/UNA/Instrução/Encerramento de Instrução/Julgamento (hoje o rascunho usa
   `1/2/3/4` como placeholders — `4` é o único herdado da query original).
3. Rodar a query 4.2 e devolver o resultado para eu confirmar os textos/padrões reais de
   `ds_movimento` dos 8 movimentos monitorados.
4. Decidir o tratamento de perícia com prazo vencido: buscar/replicar a regra do "painel de
   perícias do PAI" ou tratar como fora de escopo desta query. Ainda depende de localizar a(s)
   tabela(s) de perito/laudo (query 4.4).
5. Com os pontos acima resolvidos, finalizar `sql/audiencias_realizadas_v2_draft.sql` (rascunho
   incluído neste PR) substituindo os `-- TODO(confirmar)` restantes.
