version 17.0
clear all
set more off
capture log close

*==================================================
* Full empirical workflow (M1)
* Sample: 2016-2024 full
* Controls (B): Size Lev CashFlow Top1 ROA ato ListAge
* Mechanism: ASY step1 + moderation for Einvoice x Ofee / Einvoice x auditfee
*==================================================

global data "c:/Users/li/Desktop/way5/merged_panel_2016_2024_einvoice_M1_B_ato_ListAge.dta"
global out  "c:/Users/li/Desktop/way5/stata_output_20260428_M1_corectrl_asy_inst"

cap mkdir "$out"
log using "$out/main.log", replace text

* make user-written package installable in workspace
cap mkdir "c:/Users/li/Desktop/way5/ado"
cap mkdir "c:/Users/li/Desktop/way5/ado/plus"
sysdir set PLUS "c:/Users/li/Desktop/way5/ado/plus"
adopath ++ "c:/Users/li/Desktop/way5/ado/plus"

* packages
cap which reghdfe
if _rc ssc install reghdfe, replace
cap which require
if _rc ssc install require, replace
cap which ftools
if _rc ssc install ftools, replace
cap which esttab
if _rc ssc install estout, replace
cap which coefplot
if _rc ssc install coefplot, replace
cap which ebalance
if _rc ssc install ebalance, replace

use "$data", clear
xtset id year

local ctrls Size Lev CashFlow Top1 ROA ato ListAge

*==================================================
* Step2: descriptive stats
*==================================================
eststo clear
estpost summarize DDBTD Einvoice `ctrls' BTD Rate_dif ASY Inst auditfee Ofee Mfee SOE HHI Pollute
esttab using "$out/step2_descriptive_stats.rtf", replace ///
    cells("count(fmt(0)) mean(fmt(4)) sd(fmt(4)) min(fmt(4)) max(fmt(4))") ///
    nonumber nomtitle label

estpost correlate DDBTD Einvoice `ctrls', matrix
esttab using "$out/step2_correlation_matrix.rtf", replace unstack noobs nonumber nomtitle

reg DDBTD Einvoice `ctrls' i.year
estat vif

*==================================================
* Step3: baseline DID
*==================================================
eststo clear

*- 列(1)：仅核心解释变量
reghdfe DDBTD Einvoice, absorb(id year) vce(cluster id)
eststo m1
estadd local FirmFE "Yes"
estadd local YearFE "Yes"

*- 列(2)：+ Size, Lev
reghdfe DDBTD Einvoice Size Lev, absorb(id year) vce(cluster id)
eststo m2
estadd local FirmFE "Yes"
estadd local YearFE "Yes"

*- 列(3)：+ CashFlow, ROA, ato
reghdfe DDBTD Einvoice Size Lev CashFlow ROA ato, absorb(id year) vce(cluster id)
eststo m3
estadd local FirmFE "Yes"
estadd local YearFE "Yes"

*- 列(4)：全部控制变量
reghdfe DDBTD Einvoice Size Lev CashFlow Top1 ROA ato ListAge, absorb(id year) vce(cluster id)
eststo m4
estadd local FirmFE "Yes"
estadd local YearFE "Yes"

*- 导出表格
esttab m1 m2 m3 m4 using "$out/step3_baseline_did.rtf", replace ///
    b(%9.4f) se(%9.4f) star(* 0.10 ** 0.05 *** 0.01) ///
    order(Einvoice Size Lev CashFlow Top1 ROA ato ListAge _cons) ///
    scalars("N Obs." "r2_a Adj.R2" "FirmFE Firm FE" "YearFE Year FE") ///
    nogap ///
    title("Baseline Progressive DID") ///
    addnote("注：括号内为聚类稳健标准误，，*、**、*** 分别表示 1%、5%、10% 的显著性水平，下同。")

*==================================================
* Step4: event study / parallel trend
*==================================================
capture drop first_treat treated event_time evt_pre5 evt_m4 evt_m3 evt_m2 evt_0 evt_p1 evt_p2plus
bys id: egen first_treat = min(cond(Einvoice==1, year, .))
gen treated = first_treat < .
gen event_time = year - first_treat if treated

gen evt_pre5   = treated & event_time <= -5
gen evt_m4     = treated & event_time == -4
gen evt_m3     = treated & event_time == -3
gen evt_m2     = treated & event_time == -2
gen evt_0      = treated & event_time == 0
gen evt_p1     = treated & event_time == 1
gen evt_p2plus = treated & event_time >= 2

reghdfe DDBTD evt_pre5 evt_m4 evt_m3 evt_m2 evt_0 evt_p1 evt_p2plus `ctrls', absorb(id year) vce(cluster id)
eststo es1

test evt_pre5 evt_m4 evt_m3 evt_m2
scalar p_pretrend = r(p)
display "Parallel-trend joint test p-value = " %6.4f p_pretrend

esttab es1 using "$out/step4_event_study_table.rtf", replace ///
    b(%9.4f) se(%9.4f) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(evt_pre5 evt_m4 evt_m3 evt_m2 evt_0 evt_p1 evt_p2plus) ///
    title("Event study (base=-1)")

coefplot es1, keep(evt_pre5 evt_m4 evt_m3 evt_m2 evt_0 evt_p1 evt_p2plus) ///
    order(evt_pre5 evt_m4 evt_m3 evt_m2 evt_0 evt_p1 evt_p2plus) ///
    vertical ciopts(recast(rcap) lcolor(navy)) msymbol(O) mcolor(navy) lcolor(navy) ///
    yline(0, lcolor(gs8)) ///
    xlabel(1 "pre_5" 2 "pre_4" 3 "pre_3" 4 "pre_2" 5 "current" 6 "post_1" 7 "post_2+") ///
    xtitle("政策实施时间") ytitle("政策效应") ///
    title("Parallel Trend / Event Study (M1)") graphregion(color(white))
graph export "$out/step4_parallel_trend.png", replace width(2400)

*==================================================
* Step5: robustness
*==================================================
eststo clear

* 1) 安慰剂检验
reghdfe DDBTD Einvoice `ctrls', absorb(id year) vce(cluster id)
eststo r1
est restore r1
scalar b_actual = _b[Einvoice]
permute Einvoice beta=_b[Einvoice], reps(500) seed(20260428) nodots ///
    saving("$out/step5_placebo_perm.dta", replace): ///
    reghdfe DDBTD Einvoice `ctrls', absorb(id year) vce(cluster id)

preserve
use "$out/step5_placebo_perm.dta", clear

* 计算模拟系数的标准差，用于近似计算单次模拟的P值
egen sd_beta = sd(beta)
gen p_val = 2 * (1 - normal(abs(beta)/sd_beta))

* 黑白灰配色的双坐标轴安慰剂图
twoway ///
    (scatter p_val beta, yaxis(1) msymbol(circle) msize(medium) mcolor(black)) ///
    (kdensity beta, yaxis(2) lcolor(gs6) lwidth(medium)) ///
    , ///
    xline(`=b_actual', lpattern(dash) lcolor(gs8) lwidth(medium)) /// 
    xlabel(-0.003(0.001)0.003) /// 
    ylabel(0(0.2)1.0, axis(1) angle(0)) ///
    ylabel(0(100)500.0, axis(2) angle(0)) ///
    xtitle("估计系数") ///
    ytitle("p值", axis(1)) ///
    ytitle("核密度", axis(2)) ///
    title("安慰剂检验分布图") ///
    legend(label(1 "p值") label(2 "估计系数核密度") pos(2) cols(1) region(lcolor(none))) /// 【修改】图例放在右侧，单列显示
    graphregion(color(white)) plotregion(color(white))

graph export "$out/安慰剂检验分布图.png", replace width(2400)

* 计算整体安慰剂检验的 P 值
gen abs_beta = abs(beta)
count if abs_beta >= abs(b_actual)
scalar placebo_p = r(N) / _N
display "Placebo randomization p-value = " %6.4f placebo_p
restore

* 2) 替换被解释变量
* 列(1)：基础模型
reghdfe Rate_dif Einvoice, absorb(id year) vce(cluster id)
eststo r_rd1
estadd local Controls "否"
estadd local FirmFE "是"
estadd local YearFE "是"

* 列(2)：加入完整控制变量
reghdfe Rate_dif Einvoice `ctrls', absorb(id year) vce(cluster id)
eststo r_rd2
estadd local Controls "是"
estadd local FirmFE "是"
estadd local YearFE "是"

* 将两列结果合并导出
esttab r_rd1 r_rd2 using "$out/稳健性_1_替换被解释变量.rtf", replace ///
    b(%9.4f) se(%9.4f) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(Einvoice) /// 
    stats(N r2_a Controls FirmFE YearFE, fmt(0 4 0 0 0) labels("观测值" "调整后 R²" "控制变量" "企业固定效应" "年份固定效应")) ///
    mtitles("(1)" "(2)") ///
    title("替换被解释变量（Rate_dif）") ///
    addnotes("注：括号内为聚类稳健标准误，***、**、* 分别表示 1%、5%、10% 的显著性水平。")

* 3) 熵平衡
capture drop ever_treat w_eb eb_sample
bys id: egen ever_treat = max(Einvoice)
preserve
keep if year==2020
keep id ever_treat `ctrls'
drop if missing(id, ever_treat, Size, Lev, CashFlow, Top1, ROA, ato, ListAge)
count if ever_treat==1
scalar nt_eb = r(N)
count if ever_treat==0
scalar nc_eb = r(N)
scalar k_eb = nc_eb/nt_eb
ebalance ever_treat `ctrls', normconst(`=k_eb') generate(w_eb)
keep id w_eb
tempfile eb_ids
save `eb_ids'
restore
merge m:1 id using `eb_ids', keep(master match) nogen
gen eb_sample = !missing(w_eb)
reghdfe DDBTD Einvoice `ctrls' [aw=w_eb] if eb_sample==1, absorb(id year) vce(cluster id)
eststo r3
* 添加底部固定效应标签
estadd local FirmFE "是"
estadd local YearFE "是"

* 4) 城市聚类标准误
capture drop city_id 
encode city, gen(city_id)
reghdfe DDBTD Einvoice `ctrls', absorb(id year) vce(cluster city_id)
eststo r4
estadd local FirmFE "是"
estadd local YearFE "是"

* 5) 将这两个结果合并导出到同一个 Word 表格里
esttab r3 r4 using "$out/稳健性_综合_其他稳健性检验.rtf", replace ///
    b(%9.4f) se(%9.4f) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(Einvoice Size Lev CashFlow Top1 ROA ato ListAge _cons) /// 【核心修改】列出所有控制变量和常数项
    stats(N r2_a FirmFE YearFE, fmt(0 4 0 0) labels("观测值" "调整后 R²" "企业固定效应" "年份固定效应")) ///
    mtitles("熵平衡" "城市聚类") ///
    addnotes("注：括号内为聚类稳健标准误，***、**、* 分别表示 1%、5%、10% 的显著性水平。")
*==================================================
* Step6: mechanism (ASY step1 + moderation)
*==================================================
eststo clear

* ASY: part 1
reghdfe ASY Einvoice `ctrls', absorb(id year) vce(cluster id)
eststo jasy1

* Moderation: Einvoice x Ofee / Einvoice x auditfee
capture drop Einvoice_Ofee Einvoice_auditfee
gen Einvoice_Ofee = Einvoice * Ofee if !missing(Einvoice,Ofee)

reghdfe DDBTD Einvoice Ofee Einvoice_Ofee `ctrls' if !missing(DDBTD,Einvoice,Ofee,Size,Lev,CashFlow,Top1,ROA,ato,ListAge), absorb(id year) vce(cluster id)
eststo jmod1

* 导出表格
esttab jasy1 jmod1 using "$out/step6_mechanism.rtf", replace ///
    b(%9.4f) se(%9.4f) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(Einvoice Ofee Einvoice_Ofee) ///
    stats(N r2_a, fmt(0 4) labels("N" "Adj.R2")) ///
    title("Mechanism: ASY step1 + moderation")

*==================================================
* Step7: heterogeneity
*==================================================
eststo clear

reghdfe DDBTD Einvoice `ctrls' if SOE==1, absorb(id year) vce(cluster id)
eststo h1

reghdfe DDBTD Einvoice `ctrls' if SOE==0, absorb(id year) vce(cluster id)
eststo h2

sum HHI, detail
scalar med_hhi = r(p50)
capture drop high_comp
gen high_comp = HHI <= med_hhi if !missing(HHI)

reghdfe DDBTD Einvoice `ctrls' if high_comp==1, absorb(id year) vce(cluster id)
eststo h3

reghdfe DDBTD Einvoice `ctrls' if high_comp==0, absorb(id year) vce(cluster id)
eststo h4

reghdfe DDBTD Einvoice `ctrls' if Pollute==1, absorb(id year) vce(cluster id)
eststo h5

reghdfe DDBTD Einvoice `ctrls' if Pollute==0, absorb(id year) vce(cluster id)
eststo h6

esttab h1 h2 h3 h4 h5 h6 using "$out/step7_heterogeneity.rtf", replace ///
    b(%9.4f) se(%9.4f) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(Einvoice Size Lev CashFlow Top1 ROA ato ListAge _cons) /// 【修改点1】展开列出所有控制变量和常数项
    stats(N r2_a, fmt(0 4) labels("N" "Adj.R2")) ///
    mgroups("产权性质" "行业竞争程度" "行业属性", pattern(1 0 1 0 1 0)) /// 【修改点2】给大分类加表头
    mtitles("国有企业" "非国有企业" "高竞争行业" "低竞争行业" "重污染企业" "非重污染企业") /// 【修改点3】给具体组别加表头
    title("表X 异质性检验结果") /// 修改标题
    addnotes("注：括号内为聚类稳健标准误，***、**、* 分别表示 1%、5%、10% 的显著性水平。")