#!/bin/bash

echo "初始化 Chatwoot 数据库..."
echo "这个脚本将创建数据库表并加载必要的数据"
echo ""

# 运行数据库迁移
echo "运行数据库迁移..."
docker compose -f docker-compose.production.yaml run --rm rails bundle exec rails db:chatwoot_prepare

echo ""
echo "数据库初始化完成！"
echo ""
echo "注意："
echo "1. 如果这是首次安装，系统会自动创建一个超级管理员账户"
echo "2. 请查看上面的输出获取登录凭据"
echo "3. 建议立即登录并修改默认密码"