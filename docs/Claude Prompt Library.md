Absolutely — here is a **Claude Prompt Library** crafted specifically for **SwiftLint Rule Studio**, your architecture style, and the Claude → Cursor → Xcode development loop.  

This isn’t a generic list of prompts.  
It’s a **modular, reusable, subsystem‑aligned library** designed to help you:

- think strategically in Claude  
- generate high‑quality architectural artifacts  
- feed Cursor with precise implementation instructions  
- maintain reversible, observable, teachable workflows  

I’ve grouped prompts by subsystem so you can drop them into Claude whenever you’re starting a new feature, debugging a design, or refining the PRD.

---

# 📚 **Claude Prompt Library for SwiftLint Rule Studio**
### *Strategic prompts for architecture, reasoning, rule design, and system modeling*

---

# 🧱 **1. Core Architecture & System Design**

### **1.1 — Architecture Blueprint Prompt**
```
You are my strategic architecture partner. I’m building a macOS app called SwiftLint Rule Studio. 
Design a complete architecture for the subsystem I describe next. Include:

- data models
- module boundaries
- service layers
- background processing strategy
- caching strategy
- error handling
- performance considerations
- extensibility hooks
- reversible transformation paths
- edge cases and failure modes

Subsystem: [INSERT SUBSYSTEM]
```

### **1.2 — Dependency Graph Prompt**
```
Create a dependency graph for the following components. 
Show which modules depend on which, and identify cycles, risks, and recommended boundaries.

Components:
[LIST COMPONENTS]
```

### **1.3 — Reversible Transformation Design Prompt**
```
Design a reversible transformation pipeline for this feature. 
Include forward transform, reverse transform, invariants, validation, and diffing strategy.

Feature: [INSERT FEATURE]
```

---

# 📄 **2. YAML Round‑Trip Engine**

### **2.1 — Comment Preservation Strategy**
```
Design a comment-preserving YAML round-trip engine for SwiftLint configs. 
Explain how to maintain:

- key ordering
- whitespace
- inline comments
- block comments
- custom formatting

Include edge cases and fallback strategies.
```

### **2.2 — Diff Engine Specification**
```
Specify a diff engine for YAML configuration changes. 
Include:

- algorithm choice (Myers, patience, histogram)
- how to detect semantic vs. formatting changes
- how to generate human-readable explanations
- how to ensure reversibility
```

---

# 🔍 **3. Workspace Analyzer**

### **3.1 — Incremental Analysis Heuristics**
```
Design an incremental SwiftLint analysis engine. 
Explain how to detect changed files, debounce runs, cache results, and handle large workspaces.
```

### **3.2 — Violation Storage Schema**
```
Design a SQLite/Core Data schema for storing SwiftLint violations over time. 
Include indexing strategy, retention policy, and query patterns for analytics.
```

---

# 🧭 **4. Rule Browser & Rule Detail Panel**

### **4.1 — Rule Metadata Model**
```
Define a complete data model for SwiftLint rule metadata. 
Include fields for examples, rationale, categories, parameters, and related rules.
```

### **4.2 — Impact Simulation Engine**
```
Design an impact simulation engine that estimates the effect of enabling a rule. 
Include heuristics, data sources, and UI outputs.
```

---

# 🧪 **5. Violation Inspector**

### **5.1 — Violation Grouping Logic**
```
Design a grouping and sorting strategy for violations. 
Consider grouping by file, rule, severity, and recency.
```

### **5.2 — Suppression Workflow**
```
Design a suppression workflow that is safe, auditable, and reversible. 
Include inline comments, expiration, and review workflows.
```

---

# 🧬 **6. Live Preview Mode**

### **6.1 — Snippet Analysis Engine**
```
Design a SwiftLint snippet analysis engine that runs on pasted code. 
Explain how to isolate snippet context, run linting fast, and avoid workspace interference.
```

### **6.2 — Inline Violation Rendering**
```
Design a system for rendering inline violations in a SwiftUI text editor. 
Include layout, performance, and accessibility considerations.
```

---

# 🧑‍🤝‍🧑 **7. Team Mode (Git‑Based Governance)**

### **7.1 — Proposal Workflow Design**
```
Design a Git-based proposal workflow for rule changes. 
Include branch creation, metadata storage, approval states, and conflict resolution.
```

### **7.2 — Role & Permission Model**
```
Define a role-based permission model for Team Mode. 
Include Viewer, Editor, Approver, and Admin roles with capabilities and constraints.
```

---

# 📊 **8. Dashboard & Analytics**

### **8.1 — Quality Score Algorithm**
```
Design an “Idiomatic Maturity Score” algorithm (0–100) based on rule categories, severity, and violation trends.
Explain weighting, normalization, and edge cases.
```

### **8.2 — Heatmap Rendering Strategy**
```
Design a rule-vs-file heatmap rendering engine. 
Include data aggregation, color scaling, and performance considerations.
```

---

# 🚀 **9. CI/CD Integration**

### **9.1 — CI Config Generator**
```
Design a CI configuration generator for SwiftLint. 
Include GitHub Actions, GitLab CI, Bitrise, and Jenkins templates.
```

### **9.2 — Regression Detection Logic**
```
Design a regression detection system that alerts when code quality drops. 
Include thresholds, trend analysis, and notification strategies.
```

---

# 🧩 **10. Cross‑Cutting Prompts**

### **10.1 — Risk Analysis Prompt**
```
Perform a risk analysis for this subsystem. 
Include technical risks, UX risks, performance risks, and mitigation strategies.
```

### **10.2 — Edge Case Generator**
```
List all edge cases for this feature. 
Include malformed input, concurrency issues, file system anomalies, and user error scenarios.
```

### **10.3 — Test Plan Generator**
```
Generate a comprehensive test plan for this subsystem. 
Include unit tests, integration tests, performance tests, and UI tests.
```

---

# 🧠 Want the Cursor Prompt Library next?
I can generate a **Cursor Prompt Library** that pairs with this one — tactical prompts that turn Claude’s strategic output into concrete Swift code, SwiftUI components, services, and tests.

Or, if you prefer, I can produce:

- a **Claude → Cursor → Xcode workflow guide**  
- a **feature-by-feature prompt sequence**  
- a **prompt library embedded directly into your PRD**  

Just tell me where you want to go.