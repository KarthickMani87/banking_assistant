import { useState, useRef, useEffect } from "react";
import { FaMicrophone, FaPaperPlane, FaStop } from "react-icons/fa";
import RecordRTC from "recordrtc";
import "./App.css";

// ----------- Runtime Config -----------
let runtimeConfig = null;
async function loadConfig() {
  if (!runtimeConfig) {
    const res = await fetch("/config.json", { cache: "no-store" });
    runtimeConfig = await res.json();
  }
  return runtimeConfig;
}

export default function App() {
  const [messages, setMessages] = useState([]);
  const [input, setInput] = useState("");
  const [recording, setRecording] = useState(false);
  const [jwt, setJwt] = useState(localStorage.getItem("jwt") || null);
  const [authStatus, setAuthStatus] = useState(jwt ? "✅ Logged in" : "❌ Not logged in");
  const [loginRecording, setLoginRecording] = useState(false);
  const [cfg, setCfg] = useState(null);

  // Registration state
  const [registering, setRegistering] = useState(false);
  const [regRecorder, setRegRecorder] = useState(null);
  const [regStream, setRegStream] = useState(null);
  const [regBlob, setRegBlob] = useState(null);
  const [username, setUsername] = useState("");

  const chatEndRef = useRef(null);
  const recorderRef = useRef(null);
  const streamRef = useRef(null);
  const loginRecorderRef = useRef(null);
  const loginStreamRef = useRef(null);

  // Load config.json at startup
  useEffect(() => {
    loadConfig().then(setCfg).catch((err) => {
      console.error("Failed to load config.json", err);
      setAuthStatus("❌ Config load failed");
    });
  }, []);

    // 👇 Add this effect to clear JWT on refresh
    useEffect(() => {
      localStorage.removeItem("jwt");
      setJwt(null);
      setAuthStatus("❌ Not logged in");
    }, []);

  useEffect(() => {
    chatEndRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages]);

  if (!cfg) {
    return <div className="app">⏳ Loading configuration...</div>;
  }

  // ----------- Helpers -----------
  const playBlob = (blob) => {
    const url = URL.createObjectURL(blob);
    const audio = new Audio(url);
    audio.onended = () => URL.revokeObjectURL(url);
    audio.play().catch((err) => console.warn("Audio autoplay blocked:", err));
  };

  const speak = async (text) => {
    try {
      const res = await fetch(`${cfg.TTS_URL}/tts`, {
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

  // ----------- Registration Flow -----------
  const startRegisterRecording = async () => {
    try {
      setAuthStatus("🎤 Recording your voice for registration...");
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      const recorder = new RecordRTC(stream, { type: "audio", mimeType: "audio/webm" });
      recorder.startRecording();
      setRegRecorder(recorder);
      setRegStream(stream);
      setRegistering(true);
    } catch (err) {
      setAuthStatus("❌ Mic access denied");
    }
  };

  const stopRegisterRecording = async () => {
    if (!regRecorder) return;
    await regRecorder.stopRecording(() => {
      const blob = regRecorder.getBlob();
      setRegBlob(blob);
      regStream?.getTracks().forEach((t) => t.stop());
      setRegRecorder(null);
      setRegStream(null);
      setRegistering(false);
      setAuthStatus("✅ Recording captured, you can listen and confirm to register.");
    });
  };

  const playRegistration = () => {
    if (!regBlob) return;
    playBlob(regBlob);
  };

  const confirmRegistration = async () => {
    if (!username.trim() || !regBlob) {
      alert("Please provide a username and record your voice.");
      return;
    }

    const form = new FormData();
    form.append("file", regBlob, "register.webm");

    try {
      const res = await fetch(`${cfg.VOICE_AUTH_URL}/enroll/${username}`, { method: "POST", body: form });
      if (!res.ok) throw new Error(await res.text());
      await res.json();
      setAuthStatus(`🎉 Successfully registered as ${username}`);
      setRegBlob(null);
      setUsername("");
    } catch (err) {
      setAuthStatus(`❌ Registration failed: ${err.message}`);
    }
  };

  const deleteUser = async () => {
    if (!username.trim()) {
      alert("Enter username to delete");
      return;
    }
    try {
      const res = await fetch(`${cfg.VOICE_AUTH_URL}/delete/${username}`, { method: "DELETE" });
      if (!res.ok) throw new Error(await res.text());
      setAuthStatus(`🗑️ Deleted user ${username}`);
    } catch (err) {
      setAuthStatus(`❌ Delete failed: ${err.message}`);
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
        const res = await fetch(`${cfg.VOICE_AUTH_URL}/voice-login`, { method: "POST", body: form });
        if (!res.ok) {
          throw new Error(await res.text());
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
      const res = await fetch(`${cfg.LLM_URL}/chat`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${jwt}`,
          "X-Session-ID": cfg.SESSION_ID,
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
        console.log("Sending STT request to:", cfg.STT_URL);
        const sttRes = await fetch(`${cfg.STT_URL}/transcribe`, { method: "POST", body: form });
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
        <>
          {/* Registration Panel */}
          <div className="register-panel">
            <h2>📝 Voice Registration</h2>
            <input
              type="text"
              placeholder="Enter username"
              value={username}
              onChange={(e) => setUsername(e.target.value)}
            />
            <div style={{ marginTop: 10 }}>
              <button
                onClick={registering ? stopRegisterRecording : startRegisterRecording}
                className={`reg-btn ${registering ? "recording" : ""}`}
              >
                {registering ? "⏹️ Stop Recording" : "🎙️ Record for Registration"}
              </button>
              {regBlob && (
                <>
                  <button onClick={playRegistration} style={{ marginLeft: 8 }}>▶️ Listen</button>
                  <button onClick={confirmRegistration} style={{ marginLeft: 8 }}>✅ Confirm & Register</button>
                </>
              )}
            </div>
            <button onClick={deleteUser} style={{ marginTop: 10, color: "red" }}>
              🗑️ Delete User
            </button>
          </div>

          {/* Login Panel */}
          <div className="login-panel" style={{ marginTop: 30 }}>
            <h2>🔐 Voice Login Required</h2>
            <p>{authStatus}</p>
            <button
              onClick={loginRecording ? stopLoginRecording : startLoginRecording}
              className={`login-btn ${loginRecording ? "recording" : ""}`}
            >
              {loginRecording ? "⏹️ Stop Recording" : "🎙️ Start Voice Login"}
            </button>
          </div>
        </>
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
