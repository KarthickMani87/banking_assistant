import { useState, useRef, useEffect } from "react";
import { FaMicrophone, FaPaperPlane, FaStop } from "react-icons/fa";
import RecordRTC from "recordrtc";
import "./App.css";

// ----------- Config (from .env.production) -----------
const STT_URL = import.meta.env.VITE_STT_URL;
const LLM_URL = import.meta.env.VITE_LLM_URL;
const TTS_URL = import.meta.env.VITE_TTS_URL;
const VOICE_AUTH_URL = import.meta.env.VITE_VOICE_AUTH_URL;
const SESSION_ID = import.meta.env.VITE_SESSION_ID;

export default function App() {
  const [messages, setMessages] = useState([]);
  const [input, setInput] = useState("");
  const [recording, setRecording] = useState(false);
  const [jwt, setJwt] = useState(localStorage.getItem("jwt") || null);
  const [authStatus, setAuthStatus] = useState(jwt ? "✅ Logged in" : "❌ Not logged in");
  const [loginRecording, setLoginRecording] = useState(false);

  const chatEndRef = useRef(null);
  const recorderRef = useRef(null);
  const streamRef = useRef(null);
  const loginRecorderRef = useRef(null);
  const loginStreamRef = useRef(null);

  useEffect(() => {
    chatEndRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages]);

  useEffect(() => {
    localStorage.removeItem("jwt");
    setJwt(null);
    setAuthStatus("❌ Not logged in");
  }, []);

  // ----------- Helpers -----------
  const playBlob = (blob) => {
    const url = URL.createObjectURL(blob);
    const audio = new Audio(url);
    audio.onended = () => URL.revokeObjectURL(url);
    audio.play().catch((err) => console.warn("Audio autoplay blocked:", err));
  };

  const speak = async (text) => {
    try {
      const res = await fetch(TTS_URL, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ text, audio_format: "mp3" }),
      });
      if (!res.ok) throw new Error(await res.text());
      const blob = await res.blob();
      playBlob(blob);
    } catch (e) {
      setMessages((p) => [...p, { role: "assistant", content: "TTS error: " + e.message }]);
    }
  };

  // ----------- Voice Login -----------
  const startLoginRecording = async () => {
    try {
      setAuthStatus("🎤 Recording your voice...");
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      const recorder = new RecordRTC(stream, { type: "audio", mimeType: "audio/webm" });
      recorder.startRecording();
      loginRecorderRef.current = recorder;
      loginStreamRef.current = stream;
      setLoginRecording(true);
    } catch (err) {
      setAuthStatus("❌ Mic access denied");
    }
  };

  const stopLoginRecording = async () => {
    const recorder = loginRecorderRef.current;
    if (!recorder) return;
    await recorder.stopRecording(async () => {
      const blob = recorder.getBlob();
      loginStreamRef.current?.getTracks().forEach((t) => t.stop());
      loginRecorderRef.current = null;
      loginStreamRef.current = null;
      setLoginRecording(false);

      const form = new FormData();
      form.append("file", blob, "login.webm");

      try {
        const res = await fetch(VOICE_AUTH_URL, { method: "POST", body: form });
        if (!res.ok) {
          const errText = await res.text();
          throw new Error(errText);
        }
        const data = await res.json();
        setJwt(data.token);
        localStorage.setItem("jwt", data.token);
        setAuthStatus(`✅ Authenticated as ${data.username}`);
      } catch (err) {
        setAuthStatus(`❌ Authentication failed: ${err.message}`);
      }
    });
  };

  // ----------- Chat -----------
  const sendMessage = async (text) => {
    if (!text.trim()) return;
    if (!jwt) {
      alert("You must login with voice first!");
      return;
    }

    const newMsg = { role: "user", content: text };
    setMessages((prev) => [...prev, newMsg]);

    try {
      const res = await fetch(LLM_URL, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${jwt}`,
          "X-Session-ID": SESSION_ID,
        },
        body: JSON.stringify({ message: text }),
      });

      if (!res.ok) throw new Error(await res.text());
      const data = await res.json();

      const assistantMsg = { role: "assistant", content: data.reply };
      setMessages((prev) => [...prev, assistantMsg]);

      if (data?.reply) speak(data.reply);
    } catch (err) {
      setMessages((prev) => [
        ...prev,
        { role: "assistant", content: `Error talking to LLM: ${err.message}` },
      ]);
    }
  };

  const startRecording = async () => {
    try {
      setRecording(true);
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      streamRef.current = stream;
      const recorder = new RecordRTC(stream, { type: "audio", mimeType: "audio/webm" });
      recorder.startRecording();
      recorderRef.current = recorder;
    } catch (err) {
      setRecording(false);
      alert("Mic access denied: " + err.message);
    }
  };

  const stopRecording = async () => {
    const rec = recorderRef.current;
    if (!rec) return setRecording(false);

    await rec.stopRecording(async () => {
      const blob = rec.getBlob();
      streamRef.current?.getTracks().forEach((t) => t.stop());
      recorderRef.current = null;
      streamRef.current = null;
      setRecording(false);

      const form = new FormData();
      form.append("file", blob, "recording.webm");

      try {
        const sttRes = await fetch(STT_URL, { method: "POST", body: form });
        if (!sttRes.ok) throw new Error(await sttRes.text());
        const sttData = await sttRes.json();
        if (sttData.text) sendMessage(sttData.text);
      } catch (e) {
        setMessages((p) => [...p, { role: "assistant", content: "STT Error: " + e.message }]);
      }
    });
  };

  const handleSubmit = (e) => {
    e.preventDefault();
    sendMessage(input);
    setInput("");
  };

  const handleKeyDown = (e) => {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      handleSubmit(e);
    }
  };

  return (
    <div className="app">
      {!jwt ? (
        <div className="login-panel">
          <h2>🔐 Voice Login Required</h2>
          <p>{authStatus}</p>
          <button
            onClick={loginRecording ? stopLoginRecording : startLoginRecording}
            className={`login-btn ${loginRecording ? "recording" : ""}`}
          >
            {loginRecording ? "⏹️ Stop Recording" : "🎙️ Start Voice Login"}
          </button>
        </div>
      ) : (
        <div className="chat-panel">
          <div className="chat-window">
            {messages.map((m, i) => (
              <div key={i} className={`msg ${m.role}`}>
                <div className="bubble">
                  {m.content}
                  {m.role === "assistant" && (
                    <button
                      className="speak-btn"
                      onClick={() => speak(m.content)}
                      title="Play audio"
                      style={{ marginLeft: 8 }}
                    >
                      🔊
                    </button>
                  )}
                </div>
              </div>
            ))}
            <div ref={chatEndRef} />
          </div>

          <form className="composer" onSubmit={handleSubmit}>
            <textarea
              value={input}
              onChange={(e) => setInput(e.target.value)}
              onKeyDown={handleKeyDown}
              placeholder="Type your message..."
              rows={1}
            />
            <button type="submit" className="send-btn" title="Send">
              <FaPaperPlane />
            </button>
            <button
              type="button"
              className={`mic-btn ${recording ? "recording" : ""}`}
              onClick={recording ? stopRecording : startRecording}
              title={recording ? "Stop" : "Record"}
            >
              {recording ? <FaStop /> : <FaMicrophone />}
            </button>
          </form>
        </div>
      )}
    </div>
  );
}
