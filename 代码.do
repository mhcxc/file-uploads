
//导入原始数据
use 原始数据,clear

//剔除B股样本
drop if substr(证券代码, 1, 3)=="200" |  substr(证券代码, 1, 3)=="900" 

//定义面板数据
xtset stkcd year


//缺失值处理
foreach i in 财务费用明细利息支出 财务费用明细利息收入 财务费用明细利息资本化金额 财务费用明细手续费 财务费用明细汇兑损益 财务费用明细其他 {
	replace `i'=0 if `i'==.
}


//债务融资成本Cost1: 企业财务费用占期末总负债的比重
gen 债务融资成本Cost1=财务费用/负债合计

//债务融资成本Cost2: 企业利息支出加上手续费支出和其他财务费用的总额占期末总负债的比重
gen 债务融资成本Cost2=(财务费用明细利息支出+财务费用明细手续费+财务费用明细其他)/负债合计
drop if 债务融资成本Cost1==.|债务融资成本Cost2==.


//债务融资成本Cost3: 采用企业利息支出占当年长短期负债平均值的比重来计算债务融资成本。
//其中，短期负债为资产负债表中的短期借款，长期负债包括一年内到期的长期借款、长期借款、应付债券、长期应付款及其他长期负债。
egen 长短期负债=rowtotal(短期借款 长期借款 一年内到期的长期借款 应付债券  长期应付款 其他长期负债)
gen 长短期负债均值=(长短期负债+L.长短期负债)/2
gen 债务融资成本Cost3=财务费用明细利息支出/长短期负债均值

//合并基础信息
merge 1:1 stkcd year using 行业与所属省份城市.dta, nogen keep(1 3) 
drop if 证券简称==""
order 证券代码 证券简称 stkcd year  债务融资成本Cost1 债务融资成本Cost2 债务融资成本Cost3 上市日期 行业代码 行业名称 所属省份 所属省份代码 所属城市 所属城市代码 
keep 证券代码 证券简称 stkcd year  债务融资成本Cost1 债务融资成本Cost2 债务融资成本Cost3 上市日期 行业代码 行业名称 所属省份 所属省份代码 所属城市 所属城市代码 
local var 债务融资成本Cost1 债务融资成本Cost2 债务融资成本Cost3
foreach v of varlist `var' {
   	   label var `v' "`v'"
}


//保存原始版本

save 债务融资成本（未缩尾未剔除）.dta, replace
export excel 债务融资成本（未缩尾未剔除）.xlsx, firstrow(var) keepcellfmt replace

//保存缩尾版本
winsor2 债务融资成本Cost1 债务融资成本Cost2 债务融资成本Cost3, cuts(1 99) by(year) replace

save 债务融资成本（已缩尾未剔除）.dta, replace
export excel 债务融资成本（已缩尾未剔除）.xlsx, firstrow(var) keepcellfmt replace

//保存剔除金融剔除STPT版本
drop if regexm(行业代码, "J")
foreach i in ST PT{
drop if regexm(证券简称, "`i'")
}

save 债务融资成本（已缩尾已剔除金融STPT）.dta, replace
export excel 债务融资成本（已缩尾已剔除金融STPT）.xlsx, firstrow(var) keepcellfmt replace

