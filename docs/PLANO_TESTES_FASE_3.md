# Plano de Testes - Fase 3: Validação com Dados Reais

**Status:** Em preparação para Fase 3  
**Data de criação:** 2026-09-25  
**Última atualização:** 2026-09-25

---

## 1. Escopo do Teste

### Objetivo
Validar a implementação da query `audiencias_realizadas_v2_draft.sql` contra ~100k audiências reais, comparando:
1. Classificação (Efetiva vs. Adiada) contra a query original
2. Integridade de cálculo de dias úteis (calendário)
3. Tratamento de edge cases (tipos ambíguos, regras de prioridade)
4. Performance e impacto em produção

### População de Teste
- Amostra: todas as audiências com `cd_status_audiencia = 'F'` (Realizadas) e `cd_processo_status = 'D'` (Ativo) de tipo Inicial/UNA/Instrução/Instrução-e-Julgamento
- Volume esperado: ~100.000 registros
- Período: últimos 12 meses (ou conforme limite de retenção do banco)
- Varas incluídas: todas (testar abrangência municipal do calendário)

---

## 2. Casos de Teste por Regra

### 2.1 Regra 0: Sinal Legado (Incompetência)

**Descrição:** Declarada a incompetência (941) ou Acolhida exceção de incompetência (371) dentro de 3 dias úteis → **Efetiva** (máxima prioridade)

| ID | Cenário | Setup | Esperado | Nota |
|---|---------|-------|----------|------|
| LEG-001 | Incompetência em Inicial | Inicial → 941 em janela | Efetiva | Prioridade máxima |
| LEG-002 | Incompetência em UNA | UNA → 941 em janela | Efetiva | Idem |
| LEG-003 | Incompetência em Instrução | Instrução → 941 em janela | Efetiva | Idem |
| LEG-004 | Incompetência fora da janela | Inicial → ... → 941 após 3DU | Segue regra geral | Não entra |
| LEG-005 | Evento 371 (exceção) em janela | Qualquer tipo → 371 em janela | Efetiva | Ambos eventos cobertos |

---

### 2.2 Regra 1: Regra Geral (Redesignação de Mesma Categoria)

**Descrição:** Redesignação da mesma audiência → **Adiada**

| ID | Cenário | Setup | Esperado | Nota |
|---|---------|-------|----------|------|
| RG-001 | Inicial presencial → Inicial presencial (mesma categoria) | ID 3 → ID 3 | Adiada | Exato |
| RG-002 | Inicial presencial → Inicial sumaríssimo (mesma categoria) | ID 3 → ID 16 | Adiada | Array tipo_inicial |
| RG-003 | UNA presencial → UNA videoconferência | ID 5 → ID 23 | Adiada | Array tipo_una |
| RG-004 | UNA presencial → UNA RS | ID 5 → ID 7 ou 9 | Adiada | RS incluído em tipo_una |
| RG-005 | UNA → Instrução (mudança de categoria) | ID 5 → ID 6 | Não aplica RG-001 | Regra específica 3 |
| RG-006 | Inicial presencial → Inicial sumaríssimo (proxima) | ID 3 → ID 16 + intervalo | Adiada | Detecção por array |
| RG-007 | Sem próxima audiência (Adiada por omissão) | Inicial, nunca mais redesignado | Adiada | Else do CASE |

**Notas críticas:**
- Bug corrigido: comparação anterior era por ID exato, não por array/categoria
- Implementação usa `proxima_audiencia` (ordem = 1) — só se aplica a "a próxima imediata"

---

### 2.3 Regra 2: Inicial → Qualquer Subsequente = Efetiva

**Descrição:** Inicial seguida de qualquer audiência subsequente (UNA/Instrução/Encerramento/Julgamento) → **Efetiva**

| ID | Cenário | Setup | Esperado | Nota |
|---|---------|-------|----------|------|
| INIT-001 | Inicial → UNA designada | ID 3 → ID 5 | Efetiva | Sem janela, qualquer dia |
| INIT-002 | Inicial → Instrução designada | ID 3 → ID 6 | Efetiva | Idem |
| INIT-003 | Inicial → Encerramento designado | ID 3 → ID 10 | Efetiva | Idem |
| INIT-004 | Inicial → Julgamento designado | ID 3 → ID 4 | Efetiva | Idem |
| INIT-005 | Inicial → UNA em 1 ano | ID 3 → ... → ID 5 (muito depois) | Efetiva | Sem limite de data |
| INIT-006 | Inicial → redesignação Inicial | ID 3 → ID 3 ou ID 16 | Adiada | Regra 1 prevalece |
| INIT-007 | Inicial sem nova audiência | ID 3, nenhuma após → resultado "Concluso com acordo" | Adiada? | **PENDENTE (#1)** |

**Notas críticas:**
- `audiencias_subsequentes` usa TODAS as audiências futuras (não só próxima)
- Sem limite de dias (diferente da regra UNA/Instrução)
- INIT-007 é crítica: query original marca Efetiva, novo critério está Adiada — regressão

---

### 2.4 Regra 3: UNA (Bipartição)

**Descrição:** UNA designa Instrução (bipartição) → por padrão **Adiada**, com exceções

| ID | Cenário | Setup | Esperado | Nota |
|---|---------|-------|----------|------|
| UNA-001 | UNA → Instrução (adiada por padrão) | ID 5 → ID 6, nada mais | Adiada | Default |
| UNA-002 | UNA → Instrução → Diligência + Encerramento em janela | ID 5 → ID 6 → (peça + ID 10) em 3DU | Efetiva | Regra 3a |
| UNA-003 | UNA → Instrução → Diligência SEM Encerramento | ID 5 → ID 6 → peça, sem ID 10 | Adiada | Encerramento OBRIGATÓRIO |
| UNA-004 | UNA → Instrução → Julgamento em janela | ID 5 → ID 6 → (ID 4 ou julgamento dentro 3DU) | Efetiva | Regra 3b |
| UNA-005 | UNA → Instrução → Sentença em janela | ID 5 → ID 6 → 219/220/221 em 3DU | Efetiva | Julgamento via sentença |
| UNA-006 | UNA → Instrução → Homologação acordo em janela | ID 5 → ID 6 → 466 em 3DU | Efetiva | Julgamento via transação |
| UNA-007 | UNA → Instrução → diligência (periódica fora janela) | ID 5 → ID 6 → perícia com prazo válido (mas marcada pós-3DU) | Adiada | Janela se aplica |
| UNA-008 | UNA → tipo fora escopo (redesignação) | ID 5 → ID 5 (sumaríssimo) | Adiada | Regra 1 |
| UNA-009 | UNA → tipo fora escopo (Enc.Instrução/Julgamento direto) | ID 5 → ID 10 ou ID 4 direto, pulando Instrução | Efetiva | **Regra 3d** (HIPÓTESE #2) |
| UNA-010 | UNA redesignada 2x na janela | ID 5 → ID 5 → Instrução | Adiada | Regra 1 prevalece 1ª vez |

**Notas críticas:**
- Bug corrigido: verificação anterior só olhava diligência, sem checar Encerramento também (exigido pelo documento)
- Regra 3a: `movimentos_diligencia UNION encerramento_instrucao_na_janela` (ambos necessários)
- Regra 3b: julgamento buscado em `audiencias_subsequentes`, não só `proxima_audiencia` (trata a bipartição UNA→Instrução→Julgamento)
- Regra 3d: Não está no documento, decidido pelo usuário (hipótese #2, ainda não confirmada pela SETIC)

---

### 2.5 Regra 4: Instrução (Sem Bipartição)

**Descrição:** Instrução designada diretamente (sem UNA anterior) → por padrão **Adiada**, com exceções

| ID | Cenário | Setup | Esperado | Nota |
|---|---------|-------|----------|------|
| INSTR-001 | Instrução designada (nada antes) → nada depois | ID 6, nenhuma ação | Adiada | Default |
| INSTR-002 | Instrução → Diligência + Encerramento em janela | ID 6 → (peça + ID 10) em 3DU | Efetiva | Regra 4 opção 1 |
| INSTR-003 | Instrução → Diligência SEM Encerramento | ID 6 → peça, sem ID 10 | Adiada | Encerramento OBRIGATÓRIO |
| INSTR-004 | Instrução → Julgamento em janela | ID 6 → ID 4 em 3DU | Efetiva | Regra 4 opção 2 |
| INSTR-005 | Instrução → Sentença DE MÉRITO em janela | ID 6 → 219/220/221 em 3DU | Efetiva | Via evento |
| INSTR-006 | Instrução → Julgamento Antecipado Parcial (50126) em janela | ID 6 → 50126 em 3DU | Adiada? | **PENDENTE (#5)** Sentença terminativa? |
| INSTR-007 | Instrução → Perícia ativa em janela | ID 6 → perícia com prazo válido | Efetiva | Perícia = diligência |
| INSTR-008 | Instrução → Perícia VENCIDA | ID 6 → perícia com prazo vencido | Adiada | Fora de escopo |
| INSTR-009 | Instrução, nada dentro de 3DU | ID 6 → (diligência + enc. ou julgamento) após 3DU | Adiada | Janela se aplica |
| INSTR-010 | Instrução → sem diligência e sem Julgamento | ID 6 → (nada relevante) | Adiada | **PENDENTE (#3)** Ou outra regra? |

**Notas críticas:**
- Regra 4 tem 2 caminhos: (diligência + Encerramento) OU (sem diligência + Julgamento)
- Perícia ativa (prazo válido) conta como diligência
- INSTR-010 é ambíguo: documento não cobre quando nenhuma opção se aplica

---

### 2.6 Regra 5: Perícia Ativa

**Descrição:** Perícia com laudo em aberto e prazo válido → conta como diligência

| ID | Cenário | Setup | Esperado | Nota |
|---|---------|-------|----------|------|
| PERIT-001 | Instrução → Perícia ativa em janela | ID 6 → perícia (status L/S/A/M, prazo >= CURRENT_DATE-1) | Efetiva | Se houver Encerramento |
| PERIT-002 | Instrução → Perícia ativa SEM Encerramento | ID 6 → perícia, sem ID 10 | Adiada | Mesmo que Diligência |
| PERIT-003 | Instrução → Perícia VENCIDA | ID 6 → perícia (status L/S/A/M, prazo < CURRENT_DATE-1) | Adiada | Fora de escopo (PAI) |
| PERIT-004 | Instrução → Perícia finalizada (status não em L/S/A/M) | ID 6 → perícia com status F (finalizado) | Adiada | Não conta |
| PERIT-005 | UNA → Instrução → Perícia em janela + Encerramento + Julgamento | ID 5 → 6 → (perícia + 10 + 4) | Efetiva | Múltiplas diligências |
| PERIT-006 | Perícia marcada em janela, prazo valid depois | ID 6 → perícia marcada em 3DU, prazo expire após | Ativo hoje? | **PENDENTE (#6)** Quando avaliar |

**Notas críticas:**
- Perícia ativa = `cd_status_pericia IN ('L','S','A','M')` + `dt_prazo_legal_parte >= CURRENT_DATE - 1 day`
- Referência de prazo válido alinhada ao painel de perícias original (CURRENT_DATE - 1)
- PERIT-006: documento não especifica se "ativo" significa "marcado na janela" ou "prazo válido na data de referência"

---

### 2.7 Regra 6: Tipo 8 "Instrução e Julgamento"

**Descrição:** Tipo 8 (audiência única com julgamento no mesmo ato) → **sempre Efetiva** (regra própria)

| ID | Cenário | Setup | Esperado | Nota |
|---|---------|-------|----------|------|
| T8-001 | Tipo 8 designado | ID 8, nada depois | Efetiva | Regra própria (julgamento já ocorreu) |
| T8-002 | Tipo 8 redesignado para Tipo 8 | ID 8 → ID 8 | Adiada | Regra 1 (mesma categoria) |
| T8-003 | Tipo 8 seguido de novo evento | ID 8 → Julgamento/evento posterior | Efetiva | Já é julgado |
| T8-004 | Tipo 8 precedido por UNA | UNA → ID 8 | Efetiva | ID 8 é o julgamento |
| T8-005 | Tipo 8 precedido por Instrução | ID 6 → ID 8 | Efetiva | ID 8 é o julgamento |

**Notas críticas:**
- Tipo 8 tem regra própria: sempre Efetiva, não segue a árvore da Instrução
- Só aplica Regra 1 (mesma categoria) se redesignado
- **PENDENTE (#4)**: Confirmação formal de que tipo 8 sempre é Efetiva (implementado como hipótese)

---

### 2.8 Regra 7: UNA Seguida de Tipo Fora do Escopo Normal

**Descrição:** UNA → Encerramento de Instrução ou Julgamento DIRETO (pulando Instrução) → **Efetiva**

| ID | Cenário | Setup | Esperado | Nota |
|---|---------|-------|----------|------|
| UNA7-001 | UNA → Encerramento Instrução (sem Instrução antes) | ID 5 → ID 10 direto | Efetiva | Regra 3d (hipótese) |
| UNA7-002 | UNA → Julgamento (sem Instrução/Encerramento antes) | ID 5 → ID 4 direto | Efetiva | Regra 3d (hipótese) |
| UNA7-003 | UNA → Sentença de mérito (sem Instrução antes) | ID 5 → 219 direto | Efetiva | Via 3d |
| UNA7-004 | UNA → tipo fora do escopo (ex.: Conciliação) | ID 5 → ID 1 ou 2 | Adiada | Não está no mapa |
| UNA7-005 | UNA → Encerramento, dentro de 3DU | ID 5 → ID 10, na janela | Efetiva | Data também importa |
| UNA7-006 | UNA → Encerramento, fora de 3DU | ID 5 → ID 10, após 3DU | Adiada | Fora de janela |

**Notas críticas:**
- Regra 3d não está no documento, decidida pelo usuário por analogia com a Inicial
- Usa `audiencias_subsequentes` para detectar, não só `proxima_audiencia`
- **PENDENTE (#2)**: Confirmação de que isso é o comportamento esperado

---

## 3. Casos de Teste por Cenário Complexo

### 3.1 Bipartição UNA → Instrução → Julgamento

**Descrição:** Sequência típica em rito trabalhista

```
UNA (ID 5) → Instrução (ID 6) → [sinal dentro 3DU] → RESULTADO
```

| ID | Sinal em 3DU | Esperado | Teste |
|---|-------------|----------|-------|
| BIP-001 | Diligência + Encerramento (ID 10) | Efetiva | UNA-002 |
| BIP-002 | Julgamento (ID 4) | Efetiva | UNA-004 |
| BIP-003 | Sentença de mérito (219–221) | Efetiva | UNA-005 |
| BIP-004 | Homologação acordo (466) | Efetiva | UNA-006 |
| BIP-005 | Perícia ativa + Encerramento | Efetiva | PERIT-001 |
| BIP-006 | Nenhum sinal | Adiada | UNA-001 |
| BIP-007 | Diligência SEM Encerramento | Adiada | UNA-003 |
| BIP-008 | Julgamento após 3DU | Adiada | UNA-004 (prazo) |

---

### 3.2 Múltiplas Redesignações

**Descrição:** Audiência redesignada várias vezes (frequente em recesso)

```
UNA (ID 5, 10/01) → UNA (ID 5, 15/01) → UNA (ID 23, 20/01) → Instrução (ID 6, 25/01)
```

| ID | Sequência | Esperado (por tipo) | Nota |
|---|-----------|----------|------|
| REDESIGN-001 | ID 5 → ID 5 (mesma categoria) | Adiada (regra 1) | Redesignação detectada |
| REDESIGN-002 | ID 5 (3x) → ID 6 | Adiada (até que sinal) | Regra 1 nas primeiras; regra 3 na passagem |
| REDESIGN-003 | Inicial (3x) → UNA | Efetiva | Regra 2 (inicial → outro) |
| REDESIGN-004 | Instrução (2x) → nada | Adiada | Regra 1 (mesma) |

---

### 3.3 Impacto do Calendário (Dias Úteis)

**Descrição:** Testes de precisão da contagem de dias úteis

| ID | Cenário | Calendário | Esperado | Teste |
|---|---------|-----------|----------|-------|
| CAL-001 | Audiência em 18/12 (sexta), sinal em 23/12 (quarta) | Recesso 20–31/12 | 23/12 está fora de 3DU? | Envolvida em BIP-008 |
| CAL-002 | Audiência em 27/12 (sexta), próximo dia útil 2/1 | Recesso 20–31/12 | 3º DU = 4/1 | Cálculo de limite_3_dias_uteis |
| CAL-003 | Audiência em 28/1, sinal em 31/1 | Sem feriados | 3DU = 31/1 (exato) | Timing edge case |
| CAL-004 | Audiência em 28/1 (SP), sinal em 31/1 | Suspensão só no RJ | Deve contar em SP varas | Abrangência municipal **PENDENTE (#8)** |
| CAL-005 | Audiência sem sinal em janela | Qualquer calendário | Adiada | Teste passivo |

**Notas críticas:**
- Calendário: `in_suspende_prazo` + `in_suspende_audiencia` = dia não-útil
- Períodos (recesso): `dt_*_final` bloqueia o intervalo inteiro
- Abrangência: nacional (id_orgao_julgador IS NULL) + São Paulo (id_estado = 26)

---

### 3.4 Prioridade de Regras

**Descrição:** Quando regras entram em conflito, qual prevalece?

| ID | Conflito | Esperado | Precedência |
|---|---------|----------|-----------|
| PRIOR-001 | Incompetência (941) vs. Regra 1 (mesma categoria) | Efetiva | Regra 0 >> Regra 1 |
| PRIOR-002 | Incompetência vs. Regra 2 (Inicial → outro) | Efetiva | Regra 0 >> Regra 2 |
| PRIOR-003 | Regra 2 (Inicial → outro) vs. Regra 1 (redesignação) | Efetiva (regra 2) | Regra 2 >> Regra 1 |
| PRIOR-004 | Regra 3 (UNA → sinal em 3DU) vs. Regra 1 (redesignação) | Adiada (regra 1) | Regra 1 >> Regra 3 |
| PRIOR-005 | Tipo 8 (regra própria) vs. Regra 1 (redesignação) | Adiada | Regra 1 >> Regra 6 |

**Implementação:** Ordem do `CASE` em `classificacao`:
1. Incompetência (regra 0)
2. Inicial com subsequente (regra 2)
3. Mesma categoria redesignada (regra 1)
4. UNA/Instrução com sinais em 3DU (regra 3/4)
5. Tipo 8 (regra 6)
6. Default: Adiada

---

## 4. Validação Contra Query Original

### 4.1 Comparação de Resultados

**SQL para validar diferenças:**

```sql
-- Audiências com classificação diferente entre v1 e v2
WITH v1 AS (
    SELECT id_processo_audiencia, classificacao AS class_v1
    FROM [query original]
),
v2 AS (
    SELECT id_processo_audiencia, classificacao AS class_v2
    FROM [query v2]
),
diffs AS (
    SELECT v1.id_processo_audiencia, v1.class_v1, v2.class_v2
    FROM v1
    FULL OUTER JOIN v2 ON v1.id_processo_audiencia = v2.id_processo_audiencia
    WHERE COALESCE(v1.class_v1, 'NULL') <> COALESCE(v2.class_v2, 'NULL')
)
SELECT class_v1, class_v2, COUNT(*) AS qtd
FROM diffs
GROUP BY 1, 2
ORDER BY qtd DESC;
```

**Regressionões esperadas:**
- INIT-007 (Inicial sem nova audiência): query original marca Efetiva, v2 marca Adiada
- Magnitude: ordem de 5–10% da população (audiências que terminam sem redesignação posterior)

---

### 4.2 Reconciliação Guiada

Para cada regressão potencial:
1. Validar a lógica contra o documento (é realmente uma mudança ou um erro na query original?)
2. Confirmar com SETIC antes de colocar em produção
3. Documentar no RESPOSTAS_SETIC_Cronograma.md

---

## 5. Execução Prática

### 5.1 Preparação

1. **Exportar dados reais:**
   ```sql
   -- Criar tabela temp com amostra de ~100k audiências
   CREATE TEMP TABLE teste_audiencias AS
   SELECT * FROM audiencias WHERE ... -- filtros conforme população acima
   ```

2. **Rodar ambas as queries:**
   ```sql
   -- v1: query original
   CREATE TABLE resultado_v1 AS SELECT ... FROM audiencias_realizadas_original ...;
   
   -- v2: draft
   CREATE TABLE resultado_v2 AS SELECT ... FROM audiencias_realizadas_v2_draft ...;
   ```

3. **Comparar:**
   ```sql
   -- Delta
   SELECT ...diffs query... -- Ver seção 4.1
   ```

### 5.2 Validação de Casos Críticos

Para cada caso crítico (INIT-007, PERIT-006, #2/#4/#5), rodar query focada:

```sql
-- Exemplo: Inicial sem nova audiência
SELECT 
    r.id_processo_audiencia,
    r.nr_processo,
    r.dta_audiencia,
    CASE WHEN EXISTS(SELECT 1 FROM audiencias_subsequentes s WHERE s.id_processo_audiencia = r.id_processo_audiencia)
        THEN 'COM subsequente' ELSE 'SEM subsequente' END AS status_sequencia,
    -- v1 vs v2 classificação
FROM audiencias_realizadas r
WHERE r.id_tipo_audiencia = ANY(tipo_inicial)
  AND NOT EXISTS(SELECT 1 FROM audiencias_subsequentes s WHERE s.id_processo_audiencia = r.id_processo_audiencia)
LIMIT 100;
```

### 5.3 Performance

- Tempo de execução esperado (v2 vs v1): +5–10% (CTEs adicionais, calendário, joins)
- Índices sugeridos: `tb_processo_audiencia(id_tipo_audiencia, cd_status_audiencia, dt_inicio)`
- Memory footprint: <500MB para ~100k audiências

---

## 6. Critérios de Sucesso para Fase 3

- [ ] Ambas as queries rodam sem erro
- [ ] v2 retorna 100% do volume de v1 (mesma população)
- [ ] Regressões identificadas e documentadas
- [ ] Cada caso crítico (#1–6, #8, #10) testado com no mínimo 1 caso real
- [ ] Performance aceitável (<2s para ~100k)
- [ ] Testes registrados em nova branch / documento de resultado

---

## 7. Bloqueadores Conhecidos

| # | Questão SETIC | Impacto no Teste | Status |
|---|-----------------|-----------------|--------|
| 1 | Inicial sem nova audiência | Regressão esperada | **Bloqueador** |
| 3 | Instrução sem sinal relevante | Edge case | Bloqueador |
| 5 | Sentença terminativa | Podem gerar falsos negativos | Bloqueador |
| 6 | Perícia ativa: quando avaliar? | Timing | Bloqueador |
| 8 | Calendário: abrangência municipal | Poucos edge cases (SP) | Menor |
| 10 | Watermark autorreferente | Não bloqueia testes, mas impacta produção | Não bloqueia Fase 3 |

---

## 8. Próximos Passos

1. **Após respostas SETIC (#1, #3, #5, #6, #8):** Ajustar query e retornar a Fase 3
2. **Paralelo (não bloqueado por SETIC):** Fase 4 (Monitoramento)
3. **Após Fase 3 OK:** Fase 5 (Produção)

---

**Mantainer:** usuário (eric.lmello2024@gmail.com)  
**Review:** Apenas quando houver respostas SETIC críticas (#1, #3, #5, #6, #8)
