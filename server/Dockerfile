# Servidor de Liznack: Node 24 + SQLite, sin dependencias externas.
FROM node:24-alpine

ENV NODE_ENV=production \
    PORT=3000 \
    DATABASE_FILE=/app/data/liznack.db \
    LIZNACK_DOCKER=1

WORKDIR /app

# No hay `npm install`: el servidor solo usa módulos que vienen con Node.
COPY package.json ./
COPY src ./src

# El proceso corre sin privilegios. El directorio de datos se crea acá con el
# dueño correcto para que el volumen nombrado herede esos permisos.
RUN mkdir -p /app/data && chown -R node:node /app
USER node

EXPOSE 3000

# Sin curl en la imagen: se consulta la salud con el fetch de Node.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:'+(process.env.PORT||3000)+'/api/salud').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["node", "--disable-warning=ExperimentalWarning", "src/server.js"]
