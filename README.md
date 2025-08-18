🎙️ Voice Auth Banking Assistant

This project is a voice-authenticated AI banking assistant. It combines speech recognition (STT), voice authentication, chat with an LLM backend, and speech synthesis (TTS) into a seamless workflow:

👉 Speak your password → authenticate → chat with the assistant → hear the reply.

📂 Project Structure
<dir>
	<li>bankUseCase/</li>
	<li>├── banking-assistant/        # Frontend (React + Vite)</li>
	<li>│   └── src/                  # Chat UI (login page, chat window, audio controls)</li>
	<li>├── chat-stack/               # Chat backend + Ollama + DB schema</li>
	<li>│   ├── backend/              # FastAPI app (LangGraph + Ollama client)</li>
	<li>│   ├── schema.sql            # DB schema (users, accounts, transactions)</li>
	<li>│   ├── seed.sql              # Sample data for testing</li>
	<li>│   └── docker-compose.yml    # Local stack (Postgres + Ollama + backend)</li>
	<li>├── stt-backend/              # Speech-to-Text microservice</li>
	<li>│   ├── app.py                # FastAPI STT service</li>
	<li>│   └── requirements.txt</li>
	<li>├── tts-backend/              # Text-to-Speech microservice</li>
	<li>│   ├── server.py             # FastAPI TTS service</li>
	<li>│   └── requirements.txt</li>
	<li>├── voiceAuth/                # Voice authentication service</li>
	<li>│   ├── voice_auth.py         # FastAPI VoiceAuth (returns JWT)</li>
	<li>│   └── requirements.txt</li>
	<li>└── infra/                    # Terraform IaC for AWS deployment</li>
	<li>    ├── base.tf               # VPC, IAM, ECS cluster</li>
	<li>    ├── stt.tf / tts.tf / voiceauth.tf / chat.tf  # ECS services</li>
	<li>    ├── cloudfront.tf         # CDN config</li>
	<li>    ├── iam.tf                # IAM roles + policies</li>
	<li>    └── variables.tf</li>
</dir>

⚡ Features

🔑 Voice Authentication → Secure login via speech (JWT issued)

🎙️ Speech-to-Text (STT) → Convert user’s voice → text

💬 Chat Backend → Banking tools + LLM reasoning via Ollama (Qwen2.5 model)

🧠 Banking Tools →

Get balance

Transfer funds

List transactions

Add beneficiaries

Fetch exchange rates

🔊 Text-to-Speech (TTS) → Reply is read back to the user

🌐 Frontend → React-based chat UI (login, chat window, mic input)

☁️ Infra → Terraform deploys to AWS ECS Fargate (scalable microservices)

🗄️ Database Schema

Defined in chat-stack/schema.sql:

CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    name TEXT UNIQUE NOT NULL
);

CREATE TABLE accounts (
    id SERIAL PRIMARY KEY,
    user_id INT REFERENCES users(id),
    balance NUMERIC NOT NULL DEFAULT 0
);

CREATE TABLE transactions (
    id SERIAL PRIMARY KEY,
    account_id INT REFERENCES accounts(id),
    amount NUMERIC NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);


➡️ Seed data is available in chat-stack/seed.sql.

🚀 Running Locally (Dev)

Start Chat Backend + DB + Ollama

cd chat-stack
docker-compose up


Start STT Service

cd stt-backend
pip install -r requirements.txt
uvicorn app:app --reload --port 8001


Start TTS Service

cd tts-backend
pip install -r requirements.txt
uvicorn server:app --reload --port 8002


Start VoiceAuth Service

cd voiceAuth
pip install -r requirements.txt
uvicorn voice_auth:app --reload --port 8003


Start Frontend (React)

cd banking-assistant
npm install
npm run dev


➡️ Open: http://localhost:5173

🌐 Deploying to AWS ECS

Terraform definitions live in infra/.

Steps:

Configure AWS CLI credentials

Edit infra/variables.tf (VPC, subnets, domain, etc.)

Run:

cd infra
terraform init
terraform apply


This provisions:

ECS Cluster + Services (stt, tts, voiceauth, chat, ollama, llm_backend)

ALB + CloudFront distribution

VPC networking (public/private subnets)

IAM roles (execution + provisioner roles)

✅ Roadmap

Add CI/CD pipeline (GitHub Actions → ECS deploy)

Harden JWT auth with AWS Secrets Manager rotation

Support VPC Endpoints (private subnets, no NAT required)

Streaming responses for faster AI replies

📜 License

MIT