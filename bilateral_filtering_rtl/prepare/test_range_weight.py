# 生成 range_weight.txt 文件：权重从255(FF)线性递减到0(00)，共256行
with open("test_range_weight.txt", "w", encoding="utf-8") as f:
    # 循环0~255，共256个差值
    for diff in range(256):
        # 计算权重：差值0→255，差值1→254 ... 差值255→0
        weight = 255 - diff
        # 转换为2位大写十六进制字符串
        hex_weight = f"{weight:02X}"
        # 写入文件，每行一个值
        f.write(hex_weight + "\n")

print("文件 range_weight.txt 生成完成！")