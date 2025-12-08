# Snell 一键安装脚本

支持多系统的一键 Snell 安装脚本，简单高效，适合快速部署。

## 支持系统
- Debian / Ubuntu / CentOS / Alpine
- Alpine（独立优化版）
- Serv00 / CT8（FreeBSD）
- 爆破模式（重置 / 清理）

## 一键安装

### Snell（Debian / Ubuntu / CentOS / Alpine）
```bash
bash <(curl -sSL https://raw.githubusercontent.com/llodys/snell/main/install.sh)
```

### Snell（独立 Alpine 版本）
```bash
bash <(curl -sSL https://raw.githubusercontent.com/llodys/snell/main/snell-alpine.sh)
```

### Snell（Serv00 / CT8 - FreeBSD 环境）
```bash
bash <(curl -sSL https://raw.githubusercontent.com/llodys/snell/main/snell-freebsd.sh)
```

### 爆破模式（重置 / 重新安装）
```bash
bash <(curl -sSL http://raw.githubusercontent.com/llodys/snell/main/reset.sh)
```

## 注意事项
- 请根据系统选择对应脚本。
- FreeBSD（Serv00/CT8）必须使用专用脚本。
- 爆破模式会覆盖原配置，请谨慎使用。

## 免责声明
本脚本仅用于学习与研究，请勿用于非法用途。  
使用脚本造成的任何后果由用户自行承担。
