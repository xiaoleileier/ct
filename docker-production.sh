#!/bin/bash

echo "构建和启动 Chatwoot 生产环境..."

# 检查外部网络是否存在
if ! docker network ls | grep -q "1panel-network"; then
    echo "错误: 1panel-network 网络不存在"
    echo "请确保 1Panel 已正确安装并创建了网络"
    exit 1
fi

# 构建镜像
echo "构建 Docker 镜像..."
docker compose -f docker compose.production.yaml build

# 启动服务
echo "启动服务..."
docker compose -f docker compose.production.yaml up -d

# 显示运行状态
echo "检查服务状态..."
docker compose -f docker compose.production.yaml ps

echo "完成！"
echo "Chatwoot 现在应该在 http://localhost:3000 运行"
echo ""
echo "查看日志: docker compose -f docker compose.production.yaml logs -f"
echo "停止服务: docker compose -f docker compose.production.yaml down"