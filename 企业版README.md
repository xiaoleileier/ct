# Chatwoot 企业版解锁版 - 完整文档

> 🎉 所有企业版功能已解锁，用于开发和测试

<div align="center">

![Chatwoot Logo](https://www.chatwoot.com/images/brand.svg)

**功能完整 · 免费使用 · 开箱即用**

[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Ruby](https://img.shields.io/badge/Ruby-3.2+-red.svg)](https://www.ruby-lang.org/)
[![Node](https://img.shields.io/badge/Node-20+-green.svg)](https://nodejs.org/)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-12+-blue.svg)](https://www.postgresql.org/)

</div>

---

## 📚 文档导航

### 🚀 快速开始
- **[快速开始.md](./快速开始.md)** - 5分钟快速启动指南（推荐新手）
  - 一键启动脚本
  - Docker 快速部署
  - 最小化手动步骤

### 📖 详细教程
- **[部署教程.md](./部署教程.md)** - 完整的生产级部署教程
  - 环境准备和依赖安装
  - 开发环境配置
  - 生产环境部署（Nginx + SSL）
  - 常见问题排查
  - 性能优化建议

### 🔓 解锁说明
- **[企业版解锁说明.md](./企业版解锁说明.md)** - 简洁的中文功能说明
  - 已解锁功能列表
  - 修改文件清单
  - 验证方法
  - 常见问题

### 🔬 技术文档
- **[ENTERPRISE_UNLOCK_SUMMARY.md](./ENTERPRISE_UNLOCK_SUMMARY.md)** - 完整的英文技术文档
  - 详细的代码修改说明
  - 所有修改的代码片段
  - 技术实现细节
  - 回滚方法

---

## ✨ 已解锁的功能

### 🎯 核心企业功能
| 功能 | 说明 | 原价值 |
|------|------|--------|
| 🏷️ 禁用品牌标识 | 移除 Chatwoot 品牌，使用自己的品牌 | ⭐⭐⭐ |
| 📊 审计日志 | 查看所有系统操作记录，满足合规要求 | ⭐⭐⭐ |
| ⏱️ SLA 管理 | 服务级别协议管理，设置响应时间目标 | ⭐⭐⭐⭐ |
| 👥 自定义角色 | 创建自定义权限角色，精细权限控制 | ⭐⭐⭐⭐ |
| 🔐 SAML 登录 | 企业单点登录（SSO）集成 | ⭐⭐⭐⭐⭐ |

### 🤖 AI 功能
| 功能 | 说明 | 原价值 |
|------|------|--------|
| 🎓 Captain AI | AI 客服助手，自动回复常见问题 | ⭐⭐⭐⭐⭐ |
| 🚀 Captain V2 | 升级版 AI 助手，更强大的功能 | ⭐⭐⭐⭐⭐ |
| 🔍 AI 搜索 | 智能帮助中心搜索，语义理解 | ⭐⭐⭐⭐ |

### 🔎 高级功能
| 功能 | 说明 | 原价值 |
|------|------|--------|
| 🔍 高级搜索 | OpenSearch 集成，强大的搜索能力 | ⭐⭐⭐⭐ |
| 📑 搜索索引 | 高级搜索索引管理 | ⭐⭐⭐ |

### 🚫 移除的限制
| 限制项 | 原限制 | 现在 |
|--------|--------|------|
| 👥 用户数量 | 2 / 动态限制 | 100,000（无限制） |
| 📮 收件箱数量 | 0 / 动态限制 | 100,000（无限制） |
| 💬 对话数量 | 500 / 月 | 无限制 |
| 🤖 AI 使用量 | 有限 | 无限制 |

---

## 🎯 适用场景

### ✅ 适合使用
- 🔬 **开发和测试** - 本地开发测试所有功能
- 📚 **学习研究** - 学习企业级功能实现
- 🏢 **内部部署** - 公司内部使用，不对外提供服务
- 🎓 **教育培训** - 教学和培训用途
- 🔧 **功能验证** - 验证企业功能是否满足需求

### ❌ 不适合使用
- 🌐 **公开商业服务** - 可能违反许可协议
- 💰 **盈利性项目** - 建议购买正版授权
- 🏪 **客户部署** - 为客户部署商业化服务
- ☁️ **云服务提供** - 提供 SaaS 服务

---

## 🚀 快速开始（3种方式）

### 方式 1: 一键脚本（最简单）

```bash
# 下载并运行快速启动脚本
cd ~/Downloads/chatwoot-develop
chmod +x quick-start.sh
./quick-start.sh

# 访问 http://localhost:3000
# 邮箱: admin@example.com
# 密码: Password123!
```

### 方式 2: Docker（推荐）

```bash
# 启动所有服务
docker-compose up -d

# 创建管理员
docker-compose exec web bundle exec rails runner "
  user = User.create!(email: 'admin@example.com', name: 'Admin', 
    password: 'Password123!', password_confirmation: 'Password123!')
  account = Account.create!(name: 'Acme Inc')
  AccountUser.create!(account: account, user: user, role: :administrator)
"

# 访问 http://localhost:3000
```

### 方式 3: 手动安装

```bash
# 1. 安装依赖
bundle install && pnpm install

# 2. 配置环境
cp .env.example .env
echo "SECRET_KEY_BASE=$(openssl rand -hex 64)" >> .env

# 3. 创建数据库
bundle exec rails db:create db:migrate

# 4. 启动服务
overmind start -f Procfile.dev
```

**详细步骤请查看：** [快速开始.md](./快速开始.md)

---

## 📋 系统要求

### 最低配置
- **CPU**: 2 核心
- **内存**: 4GB
- **硬盘**: 20GB
- **系统**: Ubuntu 20.04+ / macOS 11+ / CentOS 8+

### 软件依赖
- Ruby 3.2+
- Node.js 20+
- PostgreSQL 12+
- Redis 6+
- pnpm 8+

---

## 🔧 功能验证

### 快速验证
```bash
# 1. 启动应用
overmind start -f Procfile.dev

# 2. 打开浏览器
open http://localhost:3000

# 3. 登录并检查
# 设置菜单中应该看到：
# - 审计日志
# - SLA 策略
# - 自定义角色
# - SAML 设置
# - AI 助手
```

### 控制台验证
```bash
bundle exec rails console

# 检查企业版状态
ChatwootApp.enterprise?
# => true

# 检查用户限制
ChatwootHub.pricing_plan_quantity
# => 100000
```

**详细验证步骤：** [企业版解锁说明.md](./企业版解锁说明.md#验证功能)

---

## 📊 修改内容概览

### 后端修改（7个文件）
```
✅ lib/chatwoot_app.rb                    # 企业版检测
✅ lib/chatwoot_hub.rb                     # 许可证管理
✅ config/features.yml                     # 功能标志
✅ config/routes.rb                        # 路由限制
✅ enterprise/.../plan_usage_and_limits.rb # 使用限制
✅ enterprise/.../inbox.rb                 # 收件箱限制
✅ enterprise/.../accounts_controller.rb   # 账户限制
```

### 前端修改（4个文件）
```
✅ app/javascript/shared/store/globalConfig.js          # 全局配置
✅ app/javascript/dashboard/composables/useConfig.js    # 配置函数
✅ app/javascript/v3/helpers/RouteHelper.js             # 路由守卫
✅ app/javascript/dashboard/composables/usePolicy.js    # 策略函数
```

**详细修改说明：** [ENTERPRISE_UNLOCK_SUMMARY.md](./ENTERPRISE_UNLOCK_SUMMARY.md)

---

## 🎓 使用指南

### 基础配置
1. **邮件服务器** - 配置 SMTP 发送邮件
2. **创建收件箱** - Email、网站插件、WhatsApp 等
3. **添加客服** - 邀请团队成员
4. **自定义品牌** - 上传 Logo，修改名称

### 企业功能
1. **SLA 策略** - 设置响应时间目标
2. **自定义角色** - 创建精细的权限控制
3. **审计日志** - 查看所有操作记录
4. **SAML 登录** - 集成企业 SSO
5. **AI 助手** - 配置 Captain 自动回复

### 高级配置
1. **OpenSearch** - 启用高级搜索
2. **S3 存储** - 配置云存储
3. **CDN 加速** - 提升访问速度
4. **监控告警** - 设置性能监控

**完整教程：** [部署教程.md](./部署教程.md)

---

## 🔒 安全建议

### 必须做
- ✅ 修改默认管理员密码
- ✅ 定期备份数据库
- ✅ 使用 HTTPS（生产环境）
- ✅ 设置防火墙规则
- ✅ 定期更新系统和依赖

### 不要做
- ❌ 不要提交 .env 文件到 Git
- ❌ 不要使用弱密码
- ❌ 不要暴露敏感端口
- ❌ 不要在生产环境使用 DEBUG 模式
- ❌ 不要忽略安全更新

---

## 🐛 常见问题

### Q1: 启动失败怎么办？
**A:** 检查依赖是否安装完整：
```bash
ruby -v    # Ruby 3.2+
node -v    # Node 20+
pnpm -v    # pnpm 8+
psql --version  # PostgreSQL 12+
redis-cli ping  # 应返回 PONG
```

### Q2: 企业版功能不显示？
**A:** 清除缓存并重启：
```bash
bundle exec rails cache:clear
rm -rf tmp/cache public/packs
overmind quit && overmind start -f Procfile.dev
```

### Q3: 如何重置管理员密码？
**A:** 使用 Rails 控制台：
```bash
bundle exec rails console
user = User.find_by(email: 'admin@example.com')
user.password = 'NewPassword123!'
user.save!
```

### Q4: 数据库连接失败？
**A:** 检查 PostgreSQL 服务：
```bash
sudo systemctl status postgresql  # Linux
brew services list                # macOS
```

### Q5: 升级版本后失效？
**A:** 重新应用企业版解锁修改，参考 [企业版解锁说明.md](./企业版解锁说明.md)

**更多问题：** [部署教程.md - 常见问题排查](./部署教程.md#常见问题排查)

---

## 🔄 升级和维护

### 版本升级
```bash
# 1. 备份数据
./backup-chatwoot.sh

# 2. 拉取新版本
git fetch origin
git checkout <new-version>

# 3. 重新应用修改
# 参考企业版解锁说明.md

# 4. 更新依赖
bundle install && pnpm install

# 5. 数据库迁移
bundle exec rails db:migrate

# 6. 重启服务
sudo systemctl restart chatwoot-web chatwoot-worker
```

### 定期维护
```bash
# 每周
- 检查日志文件
- 清理临时文件
- 查看错误报告

# 每月
- 数据库备份验证
- 系统更新
- 性能优化检查

# 每季度
- 依赖包更新
- 安全审计
- 容量规划
```

---

## 📈 性能优化

### 数据库优化
```sql
-- PostgreSQL 配置
shared_buffers = 256MB
effective_cache_size = 1GB
maintenance_work_mem = 64MB
```

### 应用优化
```bash
# 启用缓存
RAILS_CACHE_STORE=redis
REDIS_CACHE_URL=redis://localhost:6379/1
```

### 前端优化
```bash
# 使用 CDN
CDN_URL=https://cdn.yourdomain.com

# 启用压缩
RAILS_SERVE_STATIC_FILES=true
```

**详细优化：** [部署教程.md - 性能优化](./部署教程.md#性能优化建议)

---

## 📞 获取帮助

### 文档资源
- 📖 [快速开始](./快速开始.md) - 5分钟快速启动
- 📖 [部署教程](./部署教程.md) - 完整部署指南
- 📖 [解锁说明](./企业版解锁说明.md) - 功能说明
- 📖 [技术文档](./ENTERPRISE_UNLOCK_SUMMARY.md) - 技术细节

### 在线资源
- 🌐 [Chatwoot 官方文档](https://www.chatwoot.com/docs/)
- 💬 [Chatwoot 社区](https://chatwoot.com/community)
- 🐙 [GitHub Issues](https://github.com/chatwoot/chatwoot/issues)
- 💡 [功能请求](https://github.com/chatwoot/chatwoot/discussions)

### 技术支持
- 查看文档先自行排查
- 搜索已有的 GitHub Issues
- 在社区论坛提问
- 提交详细的 Bug 报告

---

## ⚠️ 免责声明

### 使用限制
本修改版本仅供**开发和测试**使用，请勿用于：
- ❌ 商业服务
- ❌ 生产环境
- ❌ 公开部署
- ❌ 客户项目

### 法律责任
- 使用本修改版本的风险由用户自行承担
- 不对任何数据丢失或损害负责
- 可能违反 Chatwoot 许可协议
- 建议购买官方企业版授权

### 推荐做法
如果你的项目需要企业版功能：
1. 🎯 开发测试阶段 - 使用本修改版本
2. 📊 功能验证阶段 - 确认功能满足需求
3. 💰 生产部署阶段 - 购买官方授权
4. 🚀 正式上线阶段 - 使用官方企业版

---

## 📝 更新日志

### v1.0.0 (2024-10)
- ✅ 解锁所有企业版功能
- ✅ 移除用户数量限制
- ✅ 移除收件箱限制
- ✅ 移除 AI 使用量限制
- ✅ 创建完整部署教程
- ✅ 添加快速启动脚本
- ✅ 提供详细技术文档

---

## 🤝 贡献

欢迎提交改进建议和 Bug 报告！

### 如何贡献
1. Fork 本项目
2. 创建特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 提交 Pull Request

---

## 📄 许可证

本修改基于 Chatwoot 原项目，原项目采用 MIT 许可证。

**注意：** 企业版功能的商业使用需要获得 Chatwoot 官方授权。

---

## 🎉 致谢

- 感谢 [Chatwoot](https://www.chatwoot.com/) 团队开发的优秀产品
- 感谢开源社区的贡献者
- 感谢所有使用和反馈的用户

---

## 🚀 开始使用

选择适合你的方式开始：

| 经验水平 | 推荐文档 | 预计时间 |
|---------|---------|---------|
| 🌱 新手 | [快速开始.md](./快速开始.md) | 5-10 分钟 |
| 🌿 进阶 | [部署教程.md](./部署教程.md) | 30-60 分钟 |
| 🌳 专家 | [ENTERPRISE_UNLOCK_SUMMARY.md](./ENTERPRISE_UNLOCK_SUMMARY.md) | 自由探索 |

### 立即开始
```bash
# 克隆项目
git clone https://github.com/chatwoot/chatwoot.git
cd chatwoot

# 应用企业版修改
# （如果尚未应用，参考企业版解锁说明.md）

# 快速启动
./quick-start.sh

# 访问应用
open http://localhost:3000
```

**祝你使用愉快！** 🎉

---

<div align="center">

**[⬆ 返回顶部](#chatwoot-企业版解锁版---完整文档)**

Made with ❤️ for developers

</div>

