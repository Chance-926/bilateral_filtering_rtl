import math

# ===== 可修改参数 =====
SIGMA = 25.0          # 值域标准差，建议 20~50
OUTPUT_FILE = "D:/AAA_Code/bilateral_filtering_rtl/prepare/range_weight.txt"
# =====================

MAX_D = 255
SCALE = 255.0

coeff = 1.0 / (2.0 * SIGMA * SIGMA)

with open(OUTPUT_FILE, "w") as f:
    for d in range(MAX_D + 1):
        # 高斯权重
        w_float = math.exp(- (d * d) * coeff) * SCALE
        # 四舍五入取整，并限制在 0~255
        w_int = int(round(w_float))
        if w_int > 255:
            w_int = 255
        elif w_int < 0:
            w_int = 0
        # 输出两位十六进制，小写字母（$readmemh 不区分大小写）
        f.write(f"{w_int:02x}\n")

print(f"生成完成：{OUTPUT_FILE}，共 256 个值，σ = {SIGMA}")