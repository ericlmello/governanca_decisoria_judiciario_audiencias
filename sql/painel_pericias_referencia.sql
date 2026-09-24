/*
 * Painel de perícias do PAI — query de referência fornecida pelo usuário.
 * Lista perícias com laudo em aberto (não finalizado); usada tanto para prazo
 * válido quanto vencido — a diferença está em como o prazo (dt_prazo_legal_parte)
 * é interpretado depois de rodar esta consulta, não em um filtro aqui.
 *
 * Reutilizada em sql/audiencias_realizadas_v2_draft.sql (CTE movimentos_diligencia)
 * para a condição "Perícia ativa" (seção 2.5 do documento SETIC): só entra lá a
 * perícia com prazo válido (dt_prazo_legal_parte >= CURRENT_DATE); prazo vencido
 * segue as regras deste mesmo painel, fora do escopo da query de audiências.
 */
select distinct
    p.nr_processo,
    TRIM(oj.ds_orgao_julgador) as "Órgão Julgador",
    TRIM(e.ds_especialidade) as "Especialidade",
    TRIM(pdi.ds_nome_pessoa) as "Perito",
    ul.ds_login as "Login Perito",
    --COALESCE(pdi.nr_documento_identificacao, ul.ds_login) as "CPF/CNPJ Perito",
    TO_CHAR(pp.dt_marcacao, 'DD/MM/YYYY') as "Data de Marcação",
    case
        when pp.cd_status_pericia = 'L' then 'Aguardando Laudo'
        when pp.cd_status_pericia = 'S' then 'Aguardando Esclarecimentos'
        when pp.cd_status_pericia = 'A' then 'Aguardando Laudo (Ausência de partes) - LEGADO'
        when pp.cd_status_pericia = 'M' then 'Aguardando Laudo (Designada) - LEGADO'
    end as "Status Perícia",
    TO_CHAR(ppex.dt_prazo_legal_parte, 'DD/MM/YYYY') as "Prazo de Entrega",
    TO_CHAR(CURRENT_DATE - INTERVAL '1 day', 'DD/MM/YYYY') AS "Data de referência do relatório"

from
    tb_processo_pericia pp
    inner join tb_processo_trf pt on pt.id_processo_trf = pp.id_processo_trf
    inner join tb_processo p on p.id_processo = pt.id_processo_trf
    inner join pje.tb_orgao_julgador oj on oj.id_orgao_julgador = pt.id_orgao_julgador
    inner join pje.tb_especialidade e on e.id_especialidade = pp.id_especialidade
    left join tb_pess_doc_identificacao pdi on pdi.id_pessoa = pp.id_pessoa_perito
    left join tb_proc_parte_expediente ppex on ppex.id_processo_parte_expediente = pp.id_proc_parte_exp_ultimo
    inner join tb_processo_expediente pex on pex.id_processo_expediente = ppex.id_processo_expediente
    left join tb_usuario_login ul on ul.id_usuario = pdi.id_pessoa
where
    pp.cd_status_pericia in ('L', 'S', 'A', 'M')
    and pex.ds_origem_expediente = 'PERICIA'
    and pdi.in_principal = 'S'
