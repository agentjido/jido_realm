const providers = {local: "Local folder", docker: "Docker", apple: "Apple Container", sprites: "Sprites"};
const recipes = {phoenix: "Phoenix Mix app", typescript: "TypeScript landing page"};
const matrix = document.querySelector("#matrix");
const status = document.querySelector("#status");
const all = document.querySelector("#all");
const file = document.querySelector("#file");
const output = document.querySelector("#output");
const preview = document.querySelector("#preview");
const cells = new Map();
let runs = [];
let selected;
let runningAll = false;

for (const [provider, label] of Object.entries(providers)) {
  const row = matrix.insertRow();
  const heading = document.createElement("th");
  heading.scope = "row";
  heading.textContent = label;
  row.append(heading);

  for (const [recipe, title] of Object.entries(recipes)) {
    const cell = document.createElement("div");
    cell.className = "cell";
    const run = document.createElement("button");
    run.textContent = "Build";
    run.setAttribute("aria-label", "Build " + title + " on " + label);
    run.addEventListener("click", async () => {
      run.disabled = true;
      try {
        selected = await start(provider, recipe);
        await poll();
      } catch (error) {
        status.textContent = error.message;
        run.disabled = false;
      }
    });
    const detail = document.createElement("button");
    detail.className = "inspect";
    detail.hidden = true;
    detail.addEventListener("click", () => {
      selected = latest(provider, recipe)?.id;
      file.value = "";
      showDetails();
    });
    cell.append(run, detail);
    row.insertCell().append(cell);
    cells.set(provider + ":" + recipe, {provider, recipe, run, detail});
  }
}

all.addEventListener("click", async () => {
  runningAll = true;
  all.disabled = true;
  try {
    for (const {provider, recipe} of cells.values()) {
      if (latest(provider, recipe)?.status !== "running") await start(provider, recipe);
    }
    await poll();
  } catch (error) {
    status.textContent = error.message;
  } finally {
    runningAll = false;
    all.disabled = false;
  }
});

file.addEventListener("change", showDetails);

async function start(provider, recipe) {
  const response = await fetch("/api/runs", {
    method: "POST",
    headers: {"Content-Type": "application/json"},
    body: JSON.stringify({provider, recipe})
  });
  const result = await response.json();
  if (!response.ok) throw new Error(result.error);
  return result.id;
}

function latest(provider, recipe) {
  return runs.find(run => run.provider === provider && run.recipe === recipe);
}

async function poll() {
  const response = await fetch("/api/runs");
  if (!response.ok) throw new Error("Could not read the build status.");
  const result = await response.json();
  runs = result.runs;
  document.querySelector("#model").textContent = result.model;
  let passed = 0;
  let active = 0;

  for (const {provider, recipe, run, detail} of cells.values()) {
    const current = latest(provider, recipe);
    run.disabled = current?.status === "running";
    detail.hidden = !current;
    if (!current) continue;
    if (current.status === "passed") passed++;
    if (current.status === "running") active++;
    const title = {passed: "HTTP 200", failed: "Failed", running: "Building"}[current.status];
    detail.textContent = title;
    detail.className = "inspect " + current.status;
    detail.setAttribute("aria-label", providers[provider] + " " + recipes[recipe] + ": " + title);
  }

  all.disabled = runningAll || active > 0;
  status.textContent = passed + " of 8 previews verified" + (active ? " · " + active + " building" : "");
  showDetails();
}

function showDetails() {
  const run = runs.find(row => row.id === selected);
  document.querySelector("#empty").hidden = !!run;
  document.querySelector("#result").hidden = !run;
  preview.hidden = !run?.url;
  if (!run) return;

  if (run.url) preview.href = run.url;
  document.querySelector("#run-summary").textContent =
    providers[run.provider] + " / " + recipes[run.recipe] + " · " + run.id + (run.error ? " · " + run.error : "");

  const current = file.value;
  const paths = Object.keys(run.files);
  if (paths.join("\n") !== Array.from(file.options).slice(1).map(option => option.value).join("\n")) {
    file.replaceChildren(new Option("Build log", ""), ...paths.map(path => new Option(path, path)));
    if (paths.includes(current)) file.value = current;
  }
  output.textContent = file.value ? run.files[file.value] : run.logs.join("\n");
}

async function refresh() {
  try {
    await poll();
  } catch (error) {
    status.textContent = error.message;
  } finally {
    setTimeout(refresh, 1200);
  }
}
refresh();
