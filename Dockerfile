FROM node:20

WORKDIR /lab2

COPY package.json .

RUN npm install

RUN npm install --save-dev stacktrace-parser

COPY . .

CMD ["npx", "hardhat", "test"]