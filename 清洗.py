import pandas as pd
import numpy as np
from scipy.stats import mstats

# ==================== 1. 读取关联交易明细 ====================
# 1.xlsx: 商品交易类(01)  3.xlsx: 提供或接受劳务(03)
df1 = pd.read_excel(r"F:\制作数据部分\公司治理质量\1.xlsx")
df3 = pd.read_excel(r"F:\制作数据部分\公司治理质量\3.xlsx")

# 删除中文标题行
df1 = df1[df1['Stkcd'] != '证券代码']
df3 = df3[df3['Stkcd'] != '证券代码']

# ==================== 2. 纵向合并并汇总 ====================
df_rpt = pd.concat([df1, df3], ignore_index=True)

# 提取年份、统一证券代码为6位字符串
df_rpt['年份'] = pd.to_datetime(df_rpt['Reptdt'], errors='coerce').dt.year
df_rpt['企业代码'] = df_rpt['Stkcd'].astype(str).str.replace('.0', '', regex=False).str.zfill(6)
df_rpt['Isam'] = pd.to_numeric(df_rpt['Isam'], errors='coerce')

# 按企业代码+年份汇总（商品交易+劳务交易之和）
df_rpt_sum = df_rpt.groupby(['企业代码', '年份'], as_index=False)['Isam'].sum()
df_rpt_sum.rename(columns={'Isam': '关联交易总额'}, inplace=True)

# ==================== 3. 读取主数据集并清洗 ====================
df_main = pd.read_excel(r"F:\制作数据部分\公司治理质量\数据集.xlsx")

# 统一格式
df_main['企业代码'] = df_main['企业代码'].astype(str).str.replace('.0', '', regex=False).str.zfill(6)
df_main['年份'] = df_main['年份'].astype(int)

# 剔除金融行业（行业代码J开头）
df_main = df_main[~df_main['行业代码-全部行业用大类代码'].astype(str).str.startswith('J', na=False)]

# 剔除ST公司
df_main = df_main[~df_main['股票简称'].astype(str).str.contains('ST', na=False, regex=False)]

# 剔除总资产<=0的异常值
df_main = df_main[df_main['总资产'] > 0]

# ==================== 4. 合并并计算关联交易比例 ====================
df = df_main.merge(df_rpt_sum, on=['企业代码', '年份'], how='left')
df['关联交易总额'] = df['关联交易总额'].fillna(0)

df['关联交易比例'] = df['关联交易总额'] / df['总资产']
df['关联交易比例'] = df['关联交易比例'].replace([np.inf, -np.inf], np.nan)

# 1%缩尾（Winsorize）
df['关联交易比例'] = mstats.winsorize(df['关联交易比例'].fillna(0), limits=[0.01, 0.01])

# 删除重复列
if '企业代码.1' in df.columns:
    df = df.drop(columns=['企业代码.1'])

# ==================== 5. 保存结果 ====================
out_path = r"F:\制作数据部分\公司治理质量\数据集_含关联交易比例.xlsx"
df.to_excel(out_path, index=False)

print(f"样本量: {len(df)}")
print("\n关联交易比例描述性统计:")
print(df['关联交易比例'].describe())
print(f"\n已保存至: {out_path}")