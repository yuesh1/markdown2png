# 构建阶段
FROM node:20-alpine AS builder

# 安装 pnpm
RUN corepack enable && corepack prepare pnpm@9.14.2 --activate

WORKDIR /app

# 复制包管理文件
COPY package.json pnpm-lock.yaml ./

# 安装依赖
RUN pnpm install --frozen-lockfile

# 复制源代码
COPY . .

# 构建应用
RUN pnpm build

# 生产阶段
FROM nginx:alpine AS production

# 复制自定义 nginx 配置
COPY nginx.conf /etc/nginx/conf.d/default.conf

# 从构建阶段复制构建产物
COPY --from=builder /app/dist /usr/share/nginx/html

# 暴露端口
EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
