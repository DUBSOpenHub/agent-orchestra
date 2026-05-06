"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  Activity,
  ArrowRight,
  CheckCircle2,
  Copy,
  ExternalLink,
  FileText,
  GitBranch,
  Layers3,
  Music2,
  ShieldCheck,
  Sparkles,
  Terminal,
  Users,
} from "lucide-react";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Separator } from "@/components/ui/separator";
import { cn } from "@/lib/utils";

const productDescription =
  "Multi-agent fleet conductor for the GitHub Copilot CLI.";

const command =
  "agent conductor premium max on ~/dev/my-repo : final release readiness review";

const quickstart =
  "curl -fsSL https://raw.githubusercontent.com/DUBSOpenHub/agent-orchestra/main/quickstart.sh | bash\nagent-orchestra-pulse";

const typingPhrases = [
  "agent conductor premium max on ~/repo : release readiness",
  "agent conductor premium max on ~/repo : security posture review",
  "agent conductor premium max on ~/repo : migration risk audit",
  "agent conductor status run-20260505-170318",
];

const proofChips = [
  "Commander sections in harmony",
  "Append-only ledger motifs",
  "Sealed score after the run",
];

const stats = [
  { value: 5, suffix: "", label: "Commander sections", detail: "visible panes" },
  { value: 250, suffix: "+", label: "Sub-agent ensemble", detail: "per max fleet" },
  { value: 5, suffix: "", label: "Ledger motifs", detail: "proposal to broadcast" },
  { value: 4, suffix: "", label: "Scorecard movements", detail: "repeat decision" },
];

const pipelineSteps = [
  {
    icon: Users,
    title: "Cue commander sections",
    artifact: "state.json + queue",
    description:
      "Turn one mission score into five visible Terminal Stampede commander sections with bounded work.",
  },
  {
    icon: Layers3,
    title: "Bring in sub-agents",
    artifact: "child-agents.jsonl",
    description:
      "Each section brings in focused sub-agents while keeping launch proof and telemetry fresh.",
  },
  {
    icon: GitBranch,
    title: "Play from shared ledgers",
    artifact: "collab/*.jsonl",
    description:
      "Proposals, reviews, improvements, consensus, and broadcasts become append-only musical motifs.",
  },
  {
    icon: Activity,
    title: "Watch the conductor monitor",
    artifact: "orchestrator-commentary.json",
    description:
      "Track section status, sub-agent counts, confidence, queue state, and live run health without reading raw logs.",
  },
  {
    icon: ShieldCheck,
    title: "Seal the score",
    artifact: "scorecard.md",
    description:
      "Shadow Score judges quality and Fleet Scorecard answers whether the arrangement is worth running again.",
  },
];

const transcript = [
  { who: "you", text: command },
  { who: "conductor", text: "run-20260505-170318: 5 commander sections cued" },
  { who: "section-001", text: "proposal motif: release blockers mapped to auth + billing" },
  { who: "section-003", text: "review counterpoint: agrees on auth risk, adds migration caveat" },
  { who: "ledger", text: "p5 r18 i11 c8 b7 -> ensemble convergence locked" },
  { who: "shadow-score", text: "seal verified - synthesis score: strong" },
  { who: "fleet-scorecard", text: "repeat decision: run this arrangement again with changes" },
];

const ledgerArtifacts = [
  "proposal",
  "peer_review",
  "improvement",
  "consensus",
  "broadcast",
  "bundle.json",
  "scorecard.md",
];

const scenarios = [
  {
    title: "Release readiness",
    description:
      "Assign architecture, implementation, tests, docs, and risk to separate sections before a ship/no-ship decision.",
  },
  {
    title: "Migration risk audit",
    description:
      "Let commander sections play compatibility, data flow, rollout, and rollback themes in parallel.",
  },
  {
    title: "Security posture review",
    description:
      "Bring threat modeling, dependency posture, CI, and runtime hardening into the same score.",
  },
  {
    title: "Architecture pressure-test",
    description:
      "Let multiple sections review tradeoffs, surface dissonance, and resolve into the strongest plan.",
  },
  {
    title: "Large repo onboarding",
    description:
      "Map systems, tests, ownership, and sharp edges without listening to raw log noise for hours.",
  },
  {
    title: "Cross-cutting implementation",
    description:
      "Coordinate broad changes where a single part would miss dependencies and failure modes.",
  },
];

const scorecardSteps = [
  "Run score",
  "Seal the rubric",
  "Fleet performance",
  "Evidence index",
  "Scorecard",
];

const scorecardQuestions = [
  "What changed?",
  "What converged?",
  "What failed?",
  "Would I run it again?",
];

function useTypedText(phrases: string[]) {
  const [text, setText] = useState("");

  useEffect(() => {
    let phraseIndex = 0;
    let charIndex = 0;
    let deleting = false;
    let timeout: number;

    const tick = () => {
      const phrase = phrases[phraseIndex];

      if (!deleting) {
        charIndex += 1;
        setText(phrase.slice(0, charIndex));
        if (charIndex === phrase.length) {
          deleting = true;
          timeout = window.setTimeout(tick, 1800);
          return;
        }
        timeout = window.setTimeout(tick, 42);
        return;
      }

      charIndex -= 1;
      setText(phrase.slice(0, charIndex));
      if (charIndex === 0) {
        deleting = false;
        phraseIndex = (phraseIndex + 1) % phrases.length;
        timeout = window.setTimeout(tick, 360);
        return;
      }
      timeout = window.setTimeout(tick, 20);
    };

    timeout = window.setTimeout(tick, 500);
    return () => window.clearTimeout(timeout);
  }, [phrases]);

  return text;
}

function AnimatedNumber({
  value,
  suffix = "",
}: {
  value: number;
  suffix?: string;
}) {
  const [count, setCount] = useState(0);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const element = ref.current;
    if (!element) return;

    let frame = 0;
    const observer = new IntersectionObserver(
      ([entry]) => {
        if (!entry.isIntersecting || frame) return;

        const start = performance.now();
        const duration = 1400;
        const step = (now: number) => {
          const progress = Math.min((now - start) / duration, 1);
          const eased = 1 - Math.pow(1 - progress, 3);
          setCount(Math.round(eased * value));
          if (progress < 1) frame = window.requestAnimationFrame(step);
        };
        frame = window.requestAnimationFrame(step);
      },
      { threshold: 0.35 }
    );

    observer.observe(element);
    return () => {
      observer.disconnect();
      if (frame) window.cancelAnimationFrame(frame);
    };
  }, [value]);

  return (
    <div ref={ref} className="stat-number">
      {count}
      {suffix}
    </div>
  );
}

export default function Home() {
  const [scrolled, setScrolled] = useState(false);
  const [showTop, setShowTop] = useState(false);
  const [copied, setCopied] = useState<"command" | "quickstart" | null>(null);
  const glowRef = useRef<HTMLDivElement>(null);
  const typedCommand = useTypedText(typingPhrases);

  useEffect(() => {
    const onScroll = () => {
      setScrolled(window.scrollY > 36);
      setShowTop(window.scrollY > 680);
    };
    window.addEventListener("scroll", onScroll, { passive: true });
    onScroll();
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  useEffect(() => {
    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) entry.target.classList.add("visible");
        });
      },
      { threshold: 0.12, rootMargin: "0px 0px -48px 0px" }
    );

    document.querySelectorAll(".reveal").forEach((item) => observer.observe(item));
    return () => observer.disconnect();
  }, []);

  useEffect(() => {
    const onMove = (event: MouseEvent) => {
      if (!glowRef.current) return;
      glowRef.current.style.left = `${event.clientX}px`;
      glowRef.current.style.top = `${event.clientY}px`;
    };

    window.addEventListener("mousemove", onMove);
    return () => window.removeEventListener("mousemove", onMove);
  }, []);

  const copyText = useCallback(async (value: string, type: "command" | "quickstart") => {
    try {
      await navigator.clipboard.writeText(value);
      setCopied(type);
      window.setTimeout(() => setCopied(null), 1600);
    } catch (error) {
      console.error("Failed to copy Agent Orchestra command", error);
    }
  }, []);

  const quickstartLines = useMemo(() => quickstart.split("\n"), []);

  return (
    <main className="site-shell">
      <div ref={glowRef} className="cursor-glow" aria-hidden="true" />
      <div className="grid-bg" aria-hidden="true" />
      <div className="concert-hall" aria-hidden="true">
        <div className="curtain curtain-left" />
        <div className="curtain curtain-right" />
        <div className="stage-glow" />
        <div className="balcony-lines" />
      </div>

      <button
        className={cn("back-top", showTop && "show")}
        aria-label="Back to top"
        onClick={() => window.scrollTo({ top: 0, behavior: "smooth" })}
      >
        <ArrowRight className="size-4" />
      </button>

      <nav className={cn("site-nav", scrolled && "site-nav-scrolled")}>
        <div className="site-nav-inner">
          <a href="#top" className="brand" aria-label="Agent Orchestra home">
            <span className="brand-icon">
              <Music2 className="size-4" />
            </span>
            <span>Agent Orchestra</span>
          </a>
          <div className="nav-links">
            <a href="#how">Score</a>
            <a href="#run-playback">Playback</a>
            <a href="#pulse">Monitor</a>
            <a href="#scorecard">Scorecard</a>
            <a href="#install">Install</a>
            <Button asChild size="sm" className="button-compact">
              <a href="#install">Cue the run</a>
            </Button>
          </div>
        </div>
      </nav>

      <section id="top" className="hero-section">
        <div className="container hero-grid">
          <div className="hero-copy reveal visible">
            <h1>Agent Orchestra</h1>
            <p className="hero-description">{productDescription}</p>

            <div className="proof-chips" aria-label="Agent Orchestra proof points">
              {proofChips.map((chip) => (
                <span key={chip} className="proof-chip">
                  <CheckCircle2 className="size-4" />
                  {chip}
                </span>
              ))}
            </div>

            <div className="typed-command" aria-label="Example Agent Orchestra command">
              <Terminal className="size-4" />
              <code>{typedCommand}</code>
              <span className="cursor-blink" />
            </div>

            <div className="hero-actions">
              <Button asChild size="lg">
                <a href="#install">
                  <Terminal className="size-4" />
                  Cue the run
                </a>
              </Button>
              <Button asChild variant="outline" size="lg" className="button-outline">
                <a
                  href="https://github.com/DUBSOpenHub/agent-orchestra"
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  GitHub
                  <ExternalLink className="size-4" />
                </a>
              </Button>
            </div>
          </div>

          <div className="hero-console reveal visible" aria-label="Agent Orchestra command deck preview">
            <div className="console-topbar">
              <span className="traffic-light cyan" />
              <span className="traffic-light violet" />
              <span className="traffic-light amber" />
              <strong>Agent Orchestra · conductor score</strong>
            </div>
            <div className="console-command">
              <span>$</span>
              <code>{command}</code>
            </div>
            <div className="commander-stack">
              {[
                ["commander-001", "architecture section", "complete", "250/250"],
                ["commander-002", "security section", "active", "112 playing"],
                ["commander-003", "implementation section", "in harmony", "5 ledgers"],
              ].map(([name, role, state, metric]) => (
                <div key={name} className="commander-row">
                  <div>
                    <strong>{name}</strong>
                    <span>{role}</span>
                  </div>
                  <div className="commander-metric">
                    <span>{metric}</span>
                    <em>{state}</em>
                  </div>
                </div>
              ))}
            </div>
            <div className="console-verdict">
              <span>Shadow Score: sealed</span>
              <strong>Fleet Scorecard: play it again with changes</strong>
            </div>
          </div>
        </div>
      </section>

      <section className="stats-section" aria-label="Agent Orchestra scale">
        <div className="container">
          <div className="stats-intro reveal">
            <h2>Conduct AI fleets in concert.</h2>
          </div>
          <div className="stat-grid">
            {stats.map((stat) => (
              <div key={stat.label} className="stat-card reveal">
                <AnimatedNumber value={stat.value} suffix={stat.suffix} />
                <strong>{stat.label}</strong>
                <span>{stat.detail}</span>
              </div>
            ))}
          </div>
        </div>
      </section>

      <section id="how" className="section">
        <div className="container">
          <div className="section-header reveal">
            <Badge variant="outline">
              <GitBranch className="size-3.5" />
              The score
            </Badge>
            <h2>Every section gets a part. Every run gets a score.</h2>
            <p>
              Agent Orchestra is not a generic swarm. It is a conductor score:
              visible commander groups, bounded sub-agent fan-out, shared ledgers,
              live telemetry, and sealed scoring after the work is done.
            </p>
          </div>

          <div className="pipeline-grid">
            {pipelineSteps.map((step, index) => {
              const Icon = step.icon;
              return (
                <Card key={step.title} className="pipeline-card reveal">
                  <CardHeader>
                    <div className="pipeline-card-top">
                      <span>0{index + 1}</span>
                      <Icon className="size-5" />
                    </div>
                    <CardTitle>{step.title}</CardTitle>
                    <CardDescription>{step.artifact}</CardDescription>
                  </CardHeader>
                  <CardContent>
                    <p>{step.description}</p>
                  </CardContent>
                </Card>
              );
            })}
          </div>
        </div>
      </section>

      <section id="run-playback" className="section section-muted">
        <div className="container split-section">
          <div className="section-header compact reveal">
            <Badge variant="outline">
              <Terminal className="size-3.5" />
              Run score
            </Badge>
            <h2>Hear each section enter the arrangement.</h2>
            <p>
              A believable run playback turns the mission, commander activity,
              ledger motifs, ensemble convergence, and repeat decision into one
              readable score.
            </p>
          </div>

          <Card className="transcript-card reveal">
            <CardHeader>
              <div className="score-card-title">
                <span className="status-dot" />
                <span>Sample mission score</span>
              </div>
            </CardHeader>
            <CardContent>
              <div className="transcript-lines">
                {transcript.map((line) => (
                  <div key={`${line.who}-${line.text}`} className="transcript-line">
                    <span>{line.who}</span>
                    <p>{line.text}</p>
                  </div>
                ))}
              </div>
            </CardContent>
          </Card>
        </div>

        <div className="container artifact-marquee reveal" aria-label="Run artifacts">
          <div className="marquee-track">
            {[...ledgerArtifacts, ...ledgerArtifacts].map((item, index) => (
              <span key={`${item}-${index}`} className="marquee-chip">
                {item}
              </span>
            ))}
          </div>
        </div>
      </section>

      <section id="pulse" className="section">
        <div className="container pulse-grid">
          <div className="section-header compact reveal">
            <Badge variant="outline">
              <Activity className="size-3.5" />
              Conductor monitor
            </Badge>
            <h2>Keep the conductor monitor open while the sections play.</h2>
            <p>
              Agent Pulse turns orchestration noise into live orchestration cues:
              section status, sub-agent counts, ledger tempo, confidence, and
              recent launches while the run is active.
            </p>
          </div>

          <Card className="pulse-card dashboard-card reveal">
            <CardContent className="dashboard-content">
              <div className="dashboard-grid">
                <div className="dashboard-tile">
                  <span>Commander status</span>
                  <strong>3 active / 2 complete</strong>
                </div>
                <div className="dashboard-tile">
                  <span>Sub-agents</span>
                  <strong>112 running / 480 done</strong>
                </div>
                <div className="dashboard-tile">
                  <span>Ledger tempo</span>
                  <strong>p5 r18 i11 c8 b7</strong>
                </div>
                <div className="dashboard-tile">
                  <span>Confidence</span>
                  <strong>live</strong>
                </div>
              </div>
              <Separator className="my-5 bg-white/10" />
              <div className="mini-log">
                <p><span>09:41</span> commander-002 enters with peer review</p>
                <p><span>09:44</span> convergence broadcast adopted by 3 sections</p>
                <p><span>09:47</span> Shadow Score seal still holds pitch</p>
              </div>
            </CardContent>
          </Card>
        </div>
      </section>

      <section id="use-cases" className="section section-muted">
        <div className="container">
          <div className="section-header centered reveal">
            <Badge variant="outline">
              <Sparkles className="size-3.5" />
              Set list
            </Badge>
            <h2>Use it when one solo agent cannot carry the piece.</h2>
            <p>
              Agent Orchestra shines on broad, risky, or cross-cutting work where
              independent sections find blind spots, compare evidence, and
              resolve dissonance.
            </p>
          </div>

          <div className="scenario-grid">
            {scenarios.map((scenario) => (
              <Card key={scenario.title} className="scenario-card reveal">
                <CardHeader>
                  <CardTitle>{scenario.title}</CardTitle>
                </CardHeader>
                <CardContent>
                  <p>{scenario.description}</p>
                </CardContent>
              </Card>
            ))}
          </div>
        </div>
      </section>

      <section id="scorecard" className="section scorecard-section">
        <div className="container">
          <div className="section-header centered reveal">
            <Badge variant="outline">
              <ShieldCheck className="size-3.5" />
              Fleet Scorecard
            </Badge>
            <h2>After the work, judge the run.</h2>
            <p>
              Fleet Scorecard is the closing score for orchestration: what
              changed, what rang true, what missed, and whether the same fleet is
              worth cueing again.
            </p>
          </div>

          <Card className="scorecard-card reveal">
            <CardHeader>
              <div className="score-card-title">
                <span className="status-dot" />
                <span>FSS-L4 reference implementation</span>
              </div>
              <CardTitle>Four movements. One repeat decision.</CardTitle>
              <CardDescription>
                Agent Orchestra seals a Fleet Scorecard rubric before commander
                launch and emits the scorecard during teardown.
              </CardDescription>
            </CardHeader>
            <CardContent>
              <div className="scorecard-flow" aria-label="Fleet Scorecard protocol">
                {scorecardSteps.map((step, index) => (
                  <div key={step} className="scorecard-step">
                    <span>0{index + 1}</span>
                    <strong>{step}</strong>
                  </div>
                ))}
              </div>

              <Separator className="my-6 bg-white/10" />

              <div className="scorecard-questions">
                {scorecardQuestions.map((question) => (
                  <div key={question} className="scorecard-question">
                    <CheckCircle2 className="size-4" />
                    <span>{question}</span>
                  </div>
                ))}
              </div>

              <div className="scorecard-outcome">
                <div>
                  <span>Repeat verdict</span>
                  <strong>Run again with changes</strong>
                </div>
                <div>
                  <span>Confidence</span>
                  <strong>High</strong>
                </div>
                <div>
                  <span>Failure motif</span>
                  <strong>Partial commander bundles</strong>
                </div>
              </div>

              <div className="scorecard-actions">
                <Button asChild variant="outline" className="button-outline">
                  <a
                    href="https://github.com/DUBSOpenHub/fleet-scorecard-spec"
                    target="_blank"
                    rel="noopener noreferrer"
                  >
                    Read the spec
                    <ExternalLink className="size-4" />
                  </a>
                </Button>
              </div>
            </CardContent>
          </Card>
        </div>
      </section>

      <section id="install" className="section install-section">
        <div className="container">
          <div className="section-header centered reveal">
            <Badge variant="outline">
              <FileText className="size-3.5" />
              Opening cue
            </Badge>
            <h2>Raise the score with one command.</h2>
            <p>
              Install the helper launcher, run the local smoke gate, open Agent
              Pulse, then cue a mission with a scorecard waiting at teardown.
            </p>
          </div>

          <Card className="command-card reveal">
            <CardContent>
              <div className="command-line">
                <Terminal className="size-5" />
                <code>{command}</code>
                <Button
                  onClick={() => copyText(command, "command")}
                  size="sm"
                  className="button-compact"
                >
                  <Copy className="size-3.5" />
                  {copied === "command" ? "Copied" : "Copy"}
                </Button>
              </div>
              <Separator className="my-5 bg-white/10" />
              <div className="setup-rail">
                <div>
                  <span>01</span>
                  <strong>Install</strong>
                  <p>Clone, install helpers, and run the smoke gate.</p>
                </div>
                <div>
                  <span>02</span>
                  <strong>Open Pulse</strong>
                  <p>Keep the conductor monitor visible while the fleet plays.</p>
                </div>
                <div>
                  <span>03</span>
                  <strong>Run mission</strong>
                  <p>Cue commanders and seal the final scorecard.</p>
                </div>
              </div>
              <pre className="quickstart">
                {quickstartLines.map((line) => (
                  <span key={line}>{line}</span>
                ))}
              </pre>
              <div className="install-actions">
                <Button
                  onClick={() => copyText(quickstart, "quickstart")}
                  size="sm"
                  className="button-compact"
                >
                  <Copy className="size-3.5" />
                  {copied === "quickstart" ? "Copied" : "Copy quickstart"}
                </Button>
                <Button asChild variant="outline" size="sm" className="button-outline button-compact">
                  <a
                    href="https://github.com/DUBSOpenHub/agent-orchestra"
                    target="_blank"
                    rel="noopener noreferrer"
                  >
                    View repo
                    <ExternalLink className="size-3.5" />
                  </a>
                </Button>
              </div>
            </CardContent>
          </Card>
        </div>
      </section>
    </main>
  );
}
