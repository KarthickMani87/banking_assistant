import os
from typing import Dict, Optional, List, TypedDict
from fastapi import FastAPI, Request, Header, Depends, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

import psycopg2
from psycopg2.extras import RealDictCursor
import requests

from langchain_community.chat_models import ChatOllama
from langchain.tools import tool
from langgraph.graph import StateGraph, END
from langgraph.checkpoint.memory import MemorySaver

from fastapi.security import HTTPBearer
from jose import jwt, JWTError

# ---------------- Security ----------------
#SECRET_KEY = "supersecret"  # use env var in prod
SECRET_KEY = os.getenv("JWT_SECRET", "supersecret")

ALGORITHM = "HS256"
security = HTTPBearer()

def verify_jwt(token: str = Depends(security)):
    try:
        payload = jwt.decode(token.credentials, SECRET_KEY, algorithms=[ALGORITHM])
        return payload  # contains user info
    except JWTError:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid or expired token")

# ---------------- Config ----------------
OLLAMA_BASE_URL = os.getenv("OLLAMA_BASE_URL", "http://ollama:11434")
MODEL_NAME = os.getenv("MODEL_NAME", "qwen2.5:3b-instruct")
TEMPERATURE = float(os.getenv("TEMPERATURE", "0"))

DB_CONFIG = {
    "dbname": os.getenv("PGDATABASE"),
    "user": os.getenv("PGUSER"),
    "password": os.getenv("PGPASSWORD"),
    "host": os.getenv("PGHOST"),
    "port": os.getenv("PGPORT"),
}

CORS_ORIGINS = os.getenv("CORS_ORIGINS", "*")
origins = [o.strip() for o in CORS_ORIGINS.split(",") if o.strip()]

app = FastAPI()
app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---------------- DB Helper ----------------
def get_conn():
    return psycopg2.connect(**DB_CONFIG, cursor_factory=RealDictCursor)

# ---------------- Tools ----------------
@tool
def get_balance(user_name: str) -> str:
    """Get balance for a user."""
    with get_conn() as conn, conn.cursor() as cur:
        cur.execute("""
            SELECT a.balance
            FROM accounts a
            JOIN users u ON u.id = a.user_id
            WHERE u.name=%s
        """, (user_name,))
        row = cur.fetchone()
        return f"{user_name}'s balance is ${row['balance']}" if row else f"No account for {user_name}"

@tool
def transfer_money(from_user: str, to_user: str, amount: float) -> str:
    """Transfer money between two users atomically."""
    with get_conn() as conn, conn.cursor() as cur:
        # get sender
        cur.execute("""
            SELECT a.id, a.balance 
            FROM accounts a 
            JOIN users u ON u.id=a.user_id 
            WHERE u.name=%s
        """, (from_user,))
        acc_from = cur.fetchone()

        # get recipient
        cur.execute("""
            SELECT a.id, a.balance 
            FROM accounts a 
            JOIN users u ON u.id=a.user_id 
            WHERE u.name=%s
        """, (to_user,))
        acc_to = cur.fetchone()

        if not acc_from:
            return f"Sender {from_user} not found."

        if not acc_to:
            return (
                f"Beneficiary '{to_user}' does not exist. "
                f"Please confirm if you want to add {to_user} as a new beneficiary."
            )

        if acc_from["balance"] < amount:
            return f"Insufficient funds. {from_user} has ${acc_from['balance']}."

        # perform transfer
        new_from, new_to = acc_from["balance"] - amount, acc_to["balance"] + amount
        cur.execute("UPDATE accounts SET balance=%s WHERE id=%s", (new_from, acc_from["id"]))
        cur.execute("UPDATE accounts SET balance=%s WHERE id=%s", (new_to, acc_to["id"]))
        cur.execute(
            "INSERT INTO transactions (account_id, amount, description) VALUES (%s, %s, %s)",
            (acc_from["id"], -amount, f"Transfer to {to_user}")
        )
        cur.execute(
            "INSERT INTO transactions (account_id, amount, description) VALUES (%s, %s, %s)",
            (acc_to["id"], amount, f"Transfer from {from_user}")
        )

    return f"Transferred ${amount} from {from_user} to {to_user}. New balances: {from_user}={new_from}, {to_user}={new_to}"

@tool
def list_transactions(user_name: str, limit: int = 5) -> str:
    """List recent transactions for a user."""
    with get_conn() as conn, conn.cursor() as cur:
        cur.execute("""
            SELECT t.amount, t.description, t.created_at
            FROM transactions t
            JOIN accounts a ON a.id=t.account_id
            JOIN users u ON u.id=a.user_id
            WHERE u.name=%s
            ORDER BY t.created_at DESC
            LIMIT %s
        """, (user_name, limit))
        rows = cur.fetchall()
        return str(rows) if rows else f"No transactions for {user_name}"

@tool
def get_exchange_rate(base: str = "USD", target: str = "EUR") -> str:
    """Get current exchange rate between two currencies."""
    url = f"https://api.exchangerate.host/latest?base={base}&symbols={target}"
    try:
        resp = requests.get(url, timeout=5).json()
    except Exception as e:
        return f"Error fetching rate: {e}"

    rates = resp.get("rates")
    if not rates:
        return f"API error: {resp}"

    rate = rates.get(target)
    return f"1 {base} = {rate:.2f} {target}" if rate else f"Could not fetch rate for {base}->{target}"

@tool
def get_exchange_rate_ddg(base: str = "USD", target: str = "EUR") -> str:
    """Fetches exchange rate using DuckDuckGo Instant Answer API as a fallback."""
    query = f"{base} to {target} exchange rate"
    url = f"https://api.duckduckgo.com/?q={query}&format=json&no_redirect=1&no_html=1"
    resp = requests.get(url, timeout=5).json()
    answer = resp.get("AbstractText") or resp.get("Answer")
    return answer or f"No exchange rate info found for {base}->{target}"

@tool
def add_beneficiary(user_name: str) -> str:
    """Add a new user + account (beneficiary) with 0 balance."""
    with get_conn() as conn, conn.cursor() as cur:
        cur.execute("SELECT id FROM users WHERE name=%s", (user_name,))
        if cur.fetchone():
            return f"Beneficiary {user_name} already exists."

        cur.execute("INSERT INTO users (name) VALUES (%s) RETURNING id", (user_name,))
        new_user_id = cur.fetchone()["id"]
        cur.execute("INSERT INTO accounts (user_id, balance) VALUES (%s, %s)", (new_user_id, 0))
    return f"Beneficiary {user_name} has been added successfully."

# ---------------- LLM ----------------
llm = ChatOllama(
    base_url=OLLAMA_BASE_URL,
    model=MODEL_NAME,
    temperature=TEMPERATURE,
)

# ---------------- Graph State ----------------
class AgentState(TypedDict, total=False):
    messages: List[Dict[str, str]]
    intent: str
    db_result: str
    reasoned: str

# ---------------- Nodes ----------------
def nlu_agent(state: AgentState):
    messages = state.get("messages", [])
    if not messages:
        return {"intent": "unknown", "messages": []}
        
    user_msg = messages[-1]["content"]
    system = (
        "Classify the intent of the user query as one of: "
        "balance, transfer, transactions, exchange_rate, add_beneficiary, or conversation. "
        "Reply with only the intent keyword."
    )
    resp = llm.invoke([
        {"role": "system", "content": system},
        {"role": "user", "content": user_msg}
    ])
    return {"intent": resp.content.lower().strip(), "messages": messages}

def db_agent(state: AgentState):
    messages = state.get("messages", [])
    if not messages:
        return {"intent": "unknown", "messages": []}
    intent = state.get("intent", "").lower()
    if "balance" in intent:
        result = tools["get_balance"].invoke({"user_name": "Alice"})
    elif "transfer" in intent:
        result = tools["transfer_money"].invoke({"from_user": "Alice", "to_user": "Bob", "amount": 50})
    elif "transaction" in intent:
        result = tools["list_transactions"].invoke({"user_name": "Alice"})
    else:
        result = "I don't know how to handle that."
    return {"db_result": result, "messages": messages}

def reasoning_agent(state: AgentState):
    db_result = state.get("db_result", "No DB result available.")
    resp = llm.invoke([
        {"role": "system", "content": "Interpret DB or tool results for conversation."},
        {"role": "user", "content": str(db_result)}
    ])
    return {"reasoned": resp.content, "messages": state.get("messages", [])}

def conversation_agent(state: AgentState):
    messages = state.get("messages", [])
    reasoned = state.get("reasoned", "No reasoning available.")
    system = (
        "You are a friendly banking assistant. "
        "Keep replies concise (≤60 words). "
        "Answer only banking queries (balance, transfers, transactions, exchange rates). "
        "If asked unrelated questions, politely decline."
    )
    resp = llm.invoke([
        {"role": "system", "content": system},
        {"role": "assistant", "content": reasoned},
        messages[-1] if messages else {"role": "user", "content": ""}
    ])
    return {"messages": messages + [{"role": "assistant", "content": resp.content}]}

def info_agent(state: AgentState):
    result = tools["get_exchange_rate_ddg"].invoke({"base": "USD", "target": "EUR"})
    return {"db_result": result, "messages": state.get("messages", [])}

def beneficiary_agent(state: AgentState):
    messages = state.get("messages", [])
    user_msg = messages[-1]["content"]
    tokens = user_msg.strip().split()
    new_name = None
    if "add" in tokens:
        idx = tokens.index("add")
        if idx + 1 < len(tokens):
            new_name = tokens[idx + 1].capitalize()
    if not new_name:
        return {"db_result": "Couldn't identify the beneficiary's name. Please specify like 'add Charlie'.", "messages": messages}
    result = tools["add_beneficiary"].invoke({"user_name": new_name})
    return {"db_result": result, "messages": messages}

def route_intent(state: AgentState) -> str:
    intent = state.get("intent", "unknown").lower()
    if "balance" in intent or "transfer" in intent or "transaction" in intent:
        return "db"
    elif "beneficiary" in intent:
        return "beneficiary"    
    elif "exchange" in intent or "rate" in intent:
        return "info"
    else:
        return "conversation"

# ---------------- Build LangGraph ----------------
workflow = StateGraph(AgentState)
workflow.add_node("nlu", nlu_agent)
workflow.add_node("info", info_agent)
workflow.add_node("db", db_agent)
workflow.add_node("beneficiary", beneficiary_agent)
workflow.add_node("reasoning", reasoning_agent)
workflow.add_node("conversation", conversation_agent)

workflow.set_entry_point("nlu")
workflow.add_conditional_edges("nlu", route_intent, {
    "db": "db",
    "info": "info",
    "beneficiary": "beneficiary",
    "conversation": "conversation"
})
workflow.add_edge("beneficiary", "reasoning")
workflow.add_edge("db", "reasoning")
workflow.add_edge("info", "reasoning")
workflow.add_edge("reasoning", "conversation")
workflow.add_edge("conversation", END)

memory = MemorySaver()
graph = workflow.compile(checkpointer=memory)

# ---------------- API Schemas ----------------
class ChatIn(BaseModel):
    message: str

class ChatOut(BaseModel):
    reply: str
    session_id: str

# ---------------- Endpoints ----------------
@app.post("/chat", response_model=ChatOut)
async def chat(body: ChatIn, request: Request, x_session_id: Optional[str] = Header(default=None), user=Depends(verify_jwt)):
    session_id = x_session_id or request.client.host or "default"
    state = {"messages": [{"role": "user", "content": body.message}]}
    result = graph.invoke(state, config={"configurable": {"thread_id": session_id}}) or {}
    messages = result.get("messages", [])
    reply = messages[-1]["content"] if messages else "Sorry, I wasn't able to process that."
    return ChatOut(reply=reply, session_id=session_id)

@app.get("/healthz")
def healthz():
    return {"ok": True, "model": MODEL_NAME}
