const $ = (id) => document.getElementById(id);
const state = {
  namespace: localStorage.getItem('kcd.namespace') || 'all',
  provider: localStorage.getItem('kcd.provider') || 'docker',
  fontSize: Number(localStorage.getItem('kcd.fontSize') || 16),
  data: { deployments: [], pods: [], services: [], nodes: [], events: [], controlPlane: {} },
  writeEnabled: false,
  connected: false,
  context: '',
  autoRefreshSeconds: Number(localStorage.getItem('kcd.autoRefresh') || 0),
  autoRefreshTimer: null,
};

const providers = {
  docker: { name: 'Local Docker Desktop', hint: 'Docker Desktop supplies a local Kubernetes context when Kubernetes is enabled. No cloud login is needed.', login: 'kubectl config use-context docker-desktop', docs: 'https://docs.docker.com/desktop/features/kubernetes/' },
  kind: { name: 'Local kind', hint: 'kind runs Kubernetes nodes as Docker containers. Great for disposable labs.', login: 'kind create cluster --name lab\nkubectl cluster-info --context kind-lab', docs: 'https://kind.sigs.k8s.io/' },
  eks: { name: 'AWS EKS', hint: 'Use AWS CLI to authenticate, then update kubeconfig. The dashboard uses that kubeconfig context.', login: 'aws eks update-kubeconfig --region us-east-1 --name MY_CLUSTER\nkubectl get nodes', docs: 'https://docs.aws.amazon.com/eks/latest/userguide/create-kubeconfig.html' },
  gke: { name: 'Google GKE', hint: 'Use gcloud to fetch cluster credentials into kubeconfig.', login: 'gcloud container clusters get-credentials MY_CLUSTER --region MY_REGION --project MY_PROJECT\nkubectl get nodes', docs: 'https://cloud.google.com/kubernetes-engine/docs/how-to/cluster-access-for-kubectl' },
  aks: { name: 'Azure AKS', hint: 'Use Azure CLI to merge AKS credentials into kubeconfig.', login: 'az aks get-credentials --resource-group MY_RG --name MY_CLUSTER\nkubectl get nodes', docs: 'https://learn.microsoft.com/azure/aks/learn/quick-kubernetes-deploy-cli' },
  openshift: { name: 'Red Hat OpenShift', hint: 'OpenShift is Kubernetes plus additional platform APIs. Use oc login; kubectl-compatible resources still work.', login: 'oc login https://api.example:6443 --token=REDACTED\noc whoami\nkubectl get nodes', docs: 'https://docs.redhat.com/en/documentation/openshift_container_platform/' },
  ibm: { name: 'IBM Cloud Kubernetes Service', hint: 'Use the IBM Cloud CLI and Kubernetes plug-in to write the cluster context into kubeconfig.', login: 'ibmcloud login\nibmcloud ks cluster config --cluster MY_CLUSTER\nkubectl get nodes', docs: 'https://cloud.ibm.com/docs/containers' },
  generic: { name: 'Generic / VMware / Rancher / Other', hint: 'Any conformant cluster works if kubectl can reach it through kubeconfig. This includes many VMware and Rancher-managed clusters.', login: 'export KUBECONFIG=/path/to/kubeconfig\nkubectl config get-contexts\nkubectl get nodes', docs: 'https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/' },
};

const tabs = [
  ['overview','Overview'], ['workloads','Workloads'], ['services','Services'], ['nodes','Nodes'], ['logs','Logs'], ['command','Command Center'], ['helm','Helm + OIDC'], ['compatibility','Compatibility'], ['upgrades','Upgrades'], ['learn','Learn']
];

const refs = [
  ['Kubernetes version skew policy','https://kubernetes.io/releases/version-skew-policy/'],
  ['Kubernetes releases','https://kubernetes.io/releases/'],
  ['Helm version support policy','https://helm.sh/docs/topics/version_skew/'],
  ['Amazon EKS Kubernetes versions','https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html'],
  ['Azure AKS supported versions','https://learn.microsoft.com/azure/aks/supported-kubernetes-versions'],
  ['Google GKE release schedule','https://cloud.google.com/kubernetes-engine/docs/release-schedule'],
  ['Red Hat OpenShift documentation','https://docs.redhat.com/en/documentation/openshift_container_platform/'],
  ['IBM Cloud Kubernetes versions','https://cloud.ibm.com/docs/containers?topic=containers-cs_versions'],
  ['kubectl command reference','https://kubernetes.io/docs/reference/kubectl/'],
  ['Kubernetes API overview','https://kubernetes.io/docs/reference/using-api/'],
  ['Bitnami Keycloak Helm chart','https://github.com/bitnami/charts/tree/main/bitnami/keycloak'],
  ['Keycloak securing applications with OIDC','https://www.keycloak.org/securing-apps/overview'],
  ['Keycloak JavaScript adapter','https://www.keycloak.org/securing-apps/javascript-adapter'],
];

const providerVersionData = [
  { name:'Upstream Kubernetes', current:'Maintained branches: 1.37, 1.36, 1.35', note:'Upstream maintains the most recent three minor release branches.', url:'https://kubernetes.io/releases/version-skew-policy/' },
  { name:'AWS EKS', current:'Standard: 1.36, 1.35, 1.34', note:'1.33, 1.32, 1.31 are in extended support in the current AWS table.', url:'https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html' },
  { name:'Azure AKS', current:'1.36 GA; 1.37 preview in Sep 2026', note:'Microsoft lists AKS 1.37 GA for Oct 2026. Verify your region before planning.', url:'https://learn.microsoft.com/azure/aks/supported-kubernetes-versions' },
  { name:'Google GKE', current:'1.36 available; channels vary', note:'GKE version availability depends on release channel and region. Use the GKE release schedule and channel notes.', url:'https://cloud.google.com/kubernetes-engine/docs/release-schedule' },
  { name:'IBM Cloud Kubernetes', current:'1.36 default; 1.35 supported', note:'IBM lists 1.34 and 1.33 as deprecated in its current table.', url:'https://cloud.ibm.com/docs/containers?topic=containers-cs_versions' },
  { name:'Red Hat OpenShift', current:'OCP 4.21 → Kubernetes 1.34', note:'OCP 4.20 uses Kubernetes 1.33. OpenShift has its own lifecycle and upgrade rules.', url:'https://docs.redhat.com/en/documentation/openshift_container_platform/4.21/html/release_notes/ocp-4-21-release-notes' },
];

const helmRanges = {
  '4.3':[34,37], '4.2':[33,36], '4.1':[32,35], '4.0':[31,34],
  '3.22':[34,37], '3.21':[33,36], '3.20':[32,35], '3.19':[31,34], '3.18':[30,33], '3.17':[29,32], '3.16':[28,31], '3.15':[27,30], '3.14':[26,29], '3.13':[25,28], '3.12':[24,27]
};

function injectUtilityClasses() {
  const style = document.createElement('style');
  style.textContent = `
    .btn-primary,.btn-secondary{display:inline-flex;align-items:center;justify-content:center;border-radius:.375rem;padding:.5rem .75rem;font-size:.875rem;font-weight:600;transition:.15s}
    .btn-primary{background:#0f62fe;color:white}.btn-primary:hover{background:#0043ce}.btn-primary:disabled{opacity:.5;cursor:not-allowed}
    .btn-secondary{border:1px solid #cbd5e1;background:#fff;color:#1e293b}.btn-secondary:hover{background:#f8fafc}
    .dark .btn-secondary{border-color:#334155;background:#0f172a;color:#f1f5f9}.dark .btn-secondary:hover{background:#1e293b}
    .link-btn{font-size:.875rem;font-weight:600;color:#0f62fe}.link-btn:hover{text-decoration:underline}.dark .link-btn{color:#93c5fd}
    .input{margin-top:.25rem;width:100%;border-radius:.375rem;border:1px solid #cbd5e1;background:#fff;padding:.5rem .75rem;font-size:.875rem;color:#020617;box-shadow:0 1px 2px rgb(0 0 0/.05);outline:none}
    .input:focus{border-color:#0f62fe;box-shadow:0 0 0 3px #d0e2ff}.dark .input{border-color:#334155;background:#020617;color:#f8fafc}.dark .input:focus{box-shadow:0 0 0 3px #1e293b}
    .label{font-size:.75rem;font-weight:600;text-transform:uppercase;letter-spacing:.04em;color:#64748b}.dark .label{color:#94a3b8}
    .card,.summary-card{border:1px solid #e2e8f0;border-radius:.75rem;background:#fff;padding:1rem;box-shadow:0 8px 30px rgba(15,98,254,.10)}.dark .card,.dark .summary-card{border-color:#1e293b;background:#0f172a}
    .card-head{margin-bottom:1rem;display:flex;flex-wrap:wrap;align-items:flex-start;justify-content:space-between;gap:.5rem}.card-head h2{font-size:1.125rem;font-weight:600}.card-head p{font-size:.875rem;color:#64748b}.dark .card-head p{color:#94a3b8}
    .summary-number{margin-top:.25rem;font-size:1.875rem;line-height:2.25rem;font-weight:600}.summary-label{font-size:.875rem;color:#64748b}.dark .summary-label{color:#94a3b8}
    .badge{display:inline-flex;border-radius:9999px;padding:.25rem .625rem;font-size:.75rem;font-weight:600}.badge-good{background:#d1fae5;color:#065f46}.badge-warn{background:#fef3c7;color:#78350f}.badge-bad{background:#fee2e2;color:#991b1b}.badge-info{background:#dbeafe;color:#1e40af}
    .dark .badge-good{background:#022c22;color:#a7f3d0}.dark .badge-warn{background:#451a03;color:#fde68a}.dark .badge-bad{background:#450a0a;color:#fecaca}.dark .badge-info{background:#172554;color:#bfdbfe}
    .data-table{min-width:100%;text-align:left;font-size:.875rem}.data-table th{position:sticky;top:0;background:#f1f5f9;padding:.5rem .75rem;font-size:.75rem;text-transform:uppercase;letter-spacing:.04em;color:#475569}.dark .data-table th{background:#1e293b;color:#cbd5e1}.data-table td{border-top:1px solid #e2e8f0;padding:.5rem .75rem;vertical-align:top}.dark .data-table td{border-color:#1e293b}
    .flow-box{border:1px solid #e2e8f0;border-radius:.5rem;background:#f8fafc;padding:1rem;font-weight:600}.dark .flow-box{border-color:#334155;background:#1e293b}.flow-box span{font-size:.75rem;font-weight:400;color:#64748b}.dark .flow-box span{color:#94a3b8}.flow-arrow{display:none;align-items:center;justify-content:center;font-size:1.5rem;color:#94a3b8}
    @media(min-width:768px){.flow-arrow{display:flex}}
    .dialog-box{width:min(92vw,48rem);border:0;border-radius:.75rem;background:#fff;padding:0;color:#020617;box-shadow:0 25px 50px -12px rgb(0 0 0/.35)}.dark .dialog-box{background:#0f172a;color:#f8fafc}.dialog-box form{position:relative;padding:1.25rem}.dialog-box h2{padding-right:2.5rem;font-size:1.25rem;font-weight:600}.dialog-body{margin-top:1rem;display:grid;gap:.75rem;font-size:.875rem;line-height:1.5rem}.dialog-close{position:absolute;right:1rem;top:1rem;border-radius:.25rem;padding:.5rem}.dialog-close:hover{background:#f1f5f9}.dark .dialog-close:hover{background:#1e293b}
  `;
  document.head.appendChild(style);
}

function escapeHtml(v='') { return String(v).replace(/[&<>'"]/g, (c) => ({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c])); }
function age(ts) {
  if (!ts) return '—';
  const sec = Math.max(0, Math.floor((Date.now() - new Date(ts).getTime())/1000));
  if (sec < 60) return `${sec}s`; const min=Math.floor(sec/60); if(min<60)return `${min}m`; const hr=Math.floor(min/60); if(hr<24)return `${hr}h`; return `${Math.floor(hr/24)}d`;
}
function k8sVersion(v='') { const m=String(v).match(/v?(\d+)\.(\d+)/); return m ? {major:Number(m[1]), minor:Number(m[2]), text:`${m[1]}.${m[2]}`} : null; }
function readyCondition(item) { return item?.status?.conditions?.find(c => c.type === 'Ready')?.status === 'True'; }
function podReady(p) { const cs=p?.status?.containerStatuses || []; return cs.length>0 && cs.every(c => c.ready); }
function provider() { return providers[state.provider] || providers.generic; }

async function api(path, options={}) {
  const res = await fetch(path, { headers:{'Content-Type':'application/json', ...(options.headers||{})}, ...options });
  const type = res.headers.get('content-type') || '';
  const body = type.includes('application/json') ? await res.json() : await res.text();
  if (!res.ok) throw new Error(body?.error || body || `HTTP ${res.status}`);
  return body;
}

function setConnection(ok, text) {
  state.connected = ok;
  $('connectionDot').className = `status-dot mr-2 ${ok ? 'bg-emerald-500':'bg-red-500'}`;
  $('connectionText').textContent = text;
}

function renderProviders() {
  $('providerSelect').innerHTML = Object.entries(providers).map(([k,v]) => `<option value="${k}">${escapeHtml(v.name)}</option>`).join('');
  $('providerSelect').value = state.provider;
  renderProviderHint();
}
function renderProviderHint() {
  const p=provider();
  $('providerHint').innerHTML = `<div class="flex flex-col lg:flex-row lg:items-start lg:justify-between gap-2"><div><strong>${escapeHtml(p.name)}:</strong> ${escapeHtml(p.hint)}</div><div class="flex gap-3 shrink-0"><button class="link-btn" data-copy="${escapeHtml(p.login)}">Copy login steps</button><a class="link-btn" href="${p.docs}" target="_blank" rel="noreferrer">Official docs ↗</a></div></div><pre class="mono mt-2 whitespace-pre-wrap text-xs">${escapeHtml(p.login)}</pre>`;
  bindCopyButtons();
}
function renderTabs() {
  $('tabs').innerHTML = tabs.map(([id,label],i)=>`<button data-tab="${id}" class="px-4 py-3 text-sm font-semibold border-b-2 ${i===0?'border-ibmblue-600 text-ibmblue-600':'border-transparent text-slate-500 hover:text-slate-900 dark:hover:text-white'}">${label}</button>`).join('');
  document.querySelectorAll('[data-tab]').forEach(btn=>btn.addEventListener('click',()=>showTab(btn.dataset.tab)));
}
function showTab(id) {
  document.querySelectorAll('.tab-panel').forEach(p=>p.classList.toggle('active', p.id === `panel-${id}`));
  document.querySelectorAll('[data-tab]').forEach(b=>{
    const active=b.dataset.tab===id;
    b.classList.toggle('border-ibmblue-600',active); b.classList.toggle('text-ibmblue-600',active); b.classList.toggle('border-transparent',!active); b.classList.toggle('text-slate-500',!active);
  });
}

async function loadHelmVersion() {
  try {
    const d = await api('/api/helm/version');
    const m = String(d.version || '').match(/v?(\d+\.\d+)/);
    if (m) $('checkHelm').value = m[1];
  } catch {
    // Helm is optional. Leave the example value in place when it is not installed.
  }
}

async function loadContext() {
  try {
    const data=await api('/api/context');
    state.context=data.currentContext; state.writeEnabled=Boolean(data.writeEnabled);
    $('contextSelect').innerHTML=data.contexts.map(c=>`<option ${c===data.currentContext?'selected':''}>${escapeHtml(c)}</option>`).join('');
    $('contextText').textContent=data.currentContext || 'none';
    $('writeModeBadge').className=`badge ${state.writeEnabled?'badge-bad':'badge-warn'}`;
    $('writeModeBadge').textContent=state.writeEnabled?'WRITE ENABLED':'Read-only mode';
    $('writeHint').className=`badge ${state.writeEnabled?'badge-bad':'badge-warn'}`;
    $('writeHint').textContent=state.writeEnabled?'Write actions enabled':'Write actions disabled';
  } catch(err) {
    $('contextSelect').innerHTML='<option>No kubectl context</option>';
    $('contextText').textContent='unavailable';
    setConnection(false, 'kubectl / kubeconfig unavailable');
  }
}
async function loadNamespaces() {
  try {
    const data=await api('/api/namespaces');
    const items=data.items||[];
    $('namespaceSelect').innerHTML='<option value="all">All namespaces</option>'+items.map(n=>`<option value="${escapeHtml(n.metadata.name)}">${escapeHtml(n.metadata.name)}</option>`).join('');
    if([...$('namespaceSelect').options].some(o=>o.value===state.namespace)) $('namespaceSelect').value=state.namespace; else state.namespace='all';
  } catch {}
}

async function refresh() {
  $('refreshBtn').disabled=true; $('refreshBtn').textContent='Refreshing…';
  try {
    const d=await api(`/api/overview?namespace=${encodeURIComponent(state.namespace)}`);
    state.data={ deployments:d.deployments?.items||[], pods:d.pods?.items||[], services:d.services?.items||[], nodes:d.nodes?.items||[], events:d.events?.items||[], controlPlane:d.controlPlane||{} };
    state.writeEnabled=Boolean(d.writeEnabled);
    const sv=d.version?.serverVersion?.gitVersion || d.version?.serverVersion?.gitVersion || 'unknown';
    const cv=d.version?.clientVersion?.gitVersion || 'unknown';
    $('serverVersion').textContent=sv; $('clientVersion').textContent=cv;
    const serverMinor=k8sVersion(sv); if(serverMinor) $('checkServer').value=serverMinor.text;
    const clientMinor=k8sVersion(cv); if(clientMinor) $('checkKubectl').value=clientMinor.text;
    const kubeletMinor=k8sVersion(state.data.nodes[0]?.status?.nodeInfo?.kubeletVersion || ''); if(kubeletMinor) $('checkKubelet').value=kubeletMinor.text;
    setConnection(true,'Connected to Kubernetes API');
    renderAll();
  } catch(err) {
    setConnection(false, err.message);
    renderEmpty(err.message);
  } finally { $('refreshBtn').disabled=false; $('refreshBtn').textContent='Refresh cluster'; }
}

function renderAll() { renderSummary(); renderHealth(); renderEvents(); renderDeployments(); renderPods(); renderServices(); renderNodes(); renderLogPods(); renderCommands(); }
function renderEmpty(message) {
  $('summaryCards').innerHTML=`<div class="summary-card sm:col-span-2 xl:col-span-5"><div class="summary-label">No live cluster data</div><div class="mt-2 text-sm">${escapeHtml(message)}</div><div class="mt-3 text-sm">Try <code class="mono">kubectl get nodes</code> in your terminal first.</div></div>`;
}
function renderSummary() {
  const d=state.data;
  const readyPods=d.pods.filter(p=>p.status?.phase==='Running'&&podReady(p)).length;
  const readyNodes=d.nodes.filter(readyCondition).length;
  const availableDeps=d.deployments.filter(x=>(x.status?.availableReplicas||0)>=(x.spec?.replicas||0)).length;
  const warnings=d.events.filter(e=>e.type==='Warning').length;
  const cards=[['Deployments',`${availableDeps}/${d.deployments.length}`,'available'],['Pods',`${readyPods}/${d.pods.length}`,'running + ready'],['Services',d.services.length,'network endpoints'],['Nodes',`${readyNodes}/${d.nodes.length}`,'ready'],['Warnings',warnings,'recent events']];
  $('summaryCards').innerHTML=cards.map(([label,num,sub])=>`<div class="summary-card"><div class="summary-label">${label}</div><div class="summary-number">${num}</div><div class="text-xs text-slate-500">${sub}</div></div>`).join('');
}
function renderHealth() {
  const d=state.data; const checks=[
    ['API connection',state.connected,'Dashboard can talk to the API server'],
    ['Control plane ready',String(d.controlPlane?.readyz||'').startsWith('ok'),String(d.controlPlane?.readyz||'Not exposed').split('\n')[0]],
    ['Nodes ready',d.nodes.length>0&&d.nodes.every(readyCondition),`${d.nodes.filter(readyCondition).length} of ${d.nodes.length} ready`],
    ['Deployments available',d.deployments.every(x=>(x.status?.availableReplicas||0)>=(x.spec?.replicas||0)),`${d.deployments.filter(x=>(x.status?.availableReplicas||0)>=(x.spec?.replicas||0)).length} of ${d.deployments.length} available`],
    ['Pods healthy',d.pods.every(p=>['Succeeded'].includes(p.status?.phase)||(p.status?.phase==='Running'&&podReady(p))),`${d.pods.filter(p=>p.status?.phase==='Running'&&podReady(p)).length} running + ready`],
  ];
  $('healthGrid').innerHTML=checks.map(([name,ok,note])=>`<div class="rounded-lg border border-slate-200 p-3 dark:border-slate-700"><div class="flex items-center gap-2"><span class="status-dot ${ok?'bg-emerald-500':'bg-amber-500'}"></span><strong>${escapeHtml(name)}</strong></div><div class="mt-1 text-xs text-slate-500">${escapeHtml(note)}</div></div>`).join('');
}
function renderEvents() {
  const warnings=state.data.events.filter(e=>e.type==='Warning').slice(-12).reverse();
  $('eventList').innerHTML=warnings.length?warnings.map(e=>`<div class="rounded border border-amber-200 bg-amber-50 p-2 text-xs dark:border-amber-900 dark:bg-amber-950/50"><div class="font-semibold">${escapeHtml(e.reason||'Warning')}</div><div>${escapeHtml(e.message||'')}</div><div class="mt-1 text-slate-500">${escapeHtml(e.metadata?.namespace||'')} • ${age(e.lastTimestamp||e.eventTime||e.metadata?.creationTimestamp)} ago</div></div>`).join(''):'<div class="text-sm text-slate-500">No Warning events returned.</div>';
}
function renderDeployments() {
  $('deploymentRows').innerHTML=state.data.deployments.map(d=>{const ns=d.metadata.namespace||'default',desired=d.spec?.replicas??0,ready=d.status?.readyReplicas??0;return `<tr><td>${escapeHtml(ns)}</td><td class="font-semibold">${escapeHtml(d.metadata.name)}</td><td><span class="badge ${ready===desired?'badge-good':'badge-warn'}">${ready}/${desired}</span></td><td>${d.status?.updatedReplicas??0}</td><td>${d.status?.availableReplicas??0}</td><td>${age(d.metadata.creationTimestamp)}</td><td><div class="flex flex-wrap gap-1"><button class="link-btn" data-cmd-rollout="${escapeHtml(ns)}|${escapeHtml(d.metadata.name)}">Status</button><button class="link-btn" data-cmd-restart="${escapeHtml(ns)}|${escapeHtml(d.metadata.name)}">Restart</button></div></td></tr>`}).join('') || '<tr><td colspan="7" class="text-slate-500">No deployments found.</td></tr>';
  document.querySelectorAll('[data-cmd-rollout]').forEach(b=>b.addEventListener('click',()=>quickDeploymentAction('rollout',b.dataset.cmdRollout)));
  document.querySelectorAll('[data-cmd-restart]').forEach(b=>b.addEventListener('click',()=>quickDeploymentAction('restart',b.dataset.cmdRestart)));
}
function renderPods() {
  $('podRows').innerHTML=state.data.pods.map(p=>{const ns=p.metadata.namespace||'default',statuses=p.status?.containerStatuses||[],ready=statuses.filter(s=>s.ready).length,restarts=statuses.reduce((a,s)=>a+(s.restartCount||0),0);return `<tr><td>${escapeHtml(ns)}</td><td class="font-semibold">${escapeHtml(p.metadata.name)}</td><td>${ready}/${statuses.length}</td><td><span class="badge ${p.status?.phase==='Running'&&podReady(p)?'badge-good':p.status?.phase==='Succeeded'?'badge-info':'badge-warn'}">${escapeHtml(p.status?.phase||'Unknown')}</span></td><td>${restarts}</td><td>${escapeHtml(p.spec?.nodeName||'—')}</td><td>${age(p.metadata.creationTimestamp)}</td><td><div class="flex gap-2"><button class="link-btn" data-pod-log="${escapeHtml(ns)}|${escapeHtml(p.metadata.name)}">Logs</button><button class="link-btn" data-pod-delete="${escapeHtml(ns)}|${escapeHtml(p.metadata.name)}">Delete</button></div></td></tr>`}).join('') || '<tr><td colspan="8" class="text-slate-500">No pods found.</td></tr>';
  document.querySelectorAll('[data-pod-log]').forEach(b=>b.addEventListener('click',()=>openPodLogs(b.dataset.podLog)));
  document.querySelectorAll('[data-pod-delete]').forEach(b=>b.addEventListener('click',()=>quickPodDelete(b.dataset.podDelete)));
}
function renderServices() {
  $('serviceRows').innerHTML=state.data.services.map(s=>{const ports=(s.spec?.ports||[]).map(p=>`${p.port}${p.nodePort?`→${p.nodePort}`:''}/${p.protocol||'TCP'}`).join(', ');const ext=(s.status?.loadBalancer?.ingress||[]).map(i=>i.hostname||i.ip).join(', ')||'—';return `<tr><td>${escapeHtml(s.metadata.namespace||'default')}</td><td class="font-semibold">${escapeHtml(s.metadata.name)}</td><td>${escapeHtml(s.spec?.type||'')}</td><td class="mono text-xs">${escapeHtml(s.spec?.clusterIP||'—')}</td><td class="mono text-xs">${escapeHtml(ext)}</td><td>${escapeHtml(ports)}</td><td>${age(s.metadata.creationTimestamp)}</td></tr>`}).join('') || '<tr><td colspan="7" class="text-slate-500">No services found.</td></tr>';
}
function renderNodes() {
  $('nodeRows').innerHTML=state.data.nodes.map(n=>{const ip=(n.status?.addresses||[]).find(a=>a.type==='InternalIP')?.address||'—';const ni=n.status?.nodeInfo||{};return `<tr><td class="font-semibold">${escapeHtml(n.metadata.name)}</td><td><span class="badge ${readyCondition(n)?'badge-good':'badge-bad'}">${readyCondition(n)?'Ready':'NotReady'}</span></td><td class="mono">${escapeHtml(ni.kubeletVersion||'')}</td><td>${escapeHtml(ni.osImage||'')}</td><td>${escapeHtml(ni.containerRuntimeVersion||'')}</td><td class="mono">${escapeHtml(ip)}</td><td>${age(n.metadata.creationTimestamp)}</td></tr>`}).join('') || '<tr><td colspan="7" class="text-slate-500">No nodes found.</td></tr>';
}
function renderLogPods() {
  const opts=state.data.pods.map(p=>`<option value="${escapeHtml((p.metadata.namespace||'default')+'|'+p.metadata.name)}">${escapeHtml((p.metadata.namespace||'default')+'/'+p.metadata.name)}</option>`).join('');
  $('logPod').innerHTML=opts || '<option>No pods</option>';
}

async function loadLogs() {
  const [namespace,pod]=String($('logPod').value||'').split('|'); if(!pod)return;
  $('logOutput').textContent='Loading logs…';
  const params=new URLSearchParams({namespace,pod,tail:$('logTail').value||'200'}); if($('logContainer').value.trim())params.set('container',$('logContainer').value.trim());
  try { $('logOutput').textContent=await api(`/api/logs?${params}`); } catch(err){ $('logOutput').textContent=`ERROR: ${err.message}`; }
}
function openPodLogs(v) { const [ns,pod]=v.split('|'); showTab('logs'); const option=[...$('logPod').options].find(o=>o.value===`${ns}|${pod}`); if(option){$('logPod').value=option.value; loadLogs();} }

function commandFieldMarkup(action) {
  const depOptions=state.data.deployments.map(d=>`<option value="${escapeHtml((d.metadata.namespace||'default')+'|'+d.metadata.name)}">${escapeHtml((d.metadata.namespace||'default')+'/'+d.metadata.name)}</option>`).join('');
  const podOptions=state.data.pods.map(p=>`<option value="${escapeHtml((p.metadata.namespace||'default')+'|'+p.metadata.name)}">${escapeHtml((p.metadata.namespace||'default')+'/'+p.metadata.name)}</option>`).join('');
  if(action==='deletePod') return `<label><span class="label">Pod</span><select id="cmdTarget" class="input">${podOptions}</select></label>`;
  if(action==='scale') return `<label><span class="label">Deployment</span><select id="cmdTarget" class="input">${depOptions}</select></label><label class="block mt-3"><span class="label">Replicas</span><input id="cmdReplicas" class="input" type="number" min="0" max="500" value="2"></label>`;
  if(action==='setImage') return `<label><span class="label">Deployment</span><select id="cmdTarget" class="input">${depOptions}</select></label><div class="grid gap-3 sm:grid-cols-2 mt-3"><label><span class="label">Container</span><input id="cmdContainer" class="input" placeholder="app"></label><label><span class="label">Image</span><input id="cmdImage" class="input" placeholder="nginx:1.29"></label></div>`;
  return `<label><span class="label">Deployment</span><select id="cmdTarget" class="input">${depOptions}</select></label>`;
}
function renderCommands() {
  const action=$('commandAction').value; $('commandFields').innerHTML=commandFieldMarkup(action);
  const ns=state.namespace==='all'?'default':state.namespace;
  const examples=[`kubectl get deployments -A`,`kubectl get pods -A -o wide`,`kubectl get services -A`,`kubectl get nodes -o wide`,`kubectl get events -A --sort-by=.lastTimestamp`,`kubectl logs -n ${ns} POD --tail=200`,`kubectl rollout status -n ${ns} deployment/NAME`,`helm list -A`];
  $('kubectlExamples').innerHTML=examples.map(x=>`<div class="flex items-center gap-2 rounded border border-slate-200 p-2 dark:border-slate-700"><code class="mono flex-1 text-xs break-all">${escapeHtml(x)}</code><button class="link-btn" data-copy="${escapeHtml(x)}">Copy</button></div>`).join(''); bindCopyButtons();
}
async function runCommand() {
  const action=$('commandAction').value; const [namespace,name]=String($('cmdTarget')?.value||'').split('|'); if(!name)return;
  $('commandOutput').textContent='Running…';
  try {
    let endpoint,body={namespace};
    if(action==='rollout'){endpoint='/api/actions/rollout-status';body.deployment=name;}
    if(action==='restart'){endpoint='/api/actions/restart';body.deployment=name;}
    if(action==='scale'){endpoint='/api/actions/scale';body.deployment=name;body.replicas=Number($('cmdReplicas').value);}
    if(action==='deletePod'){endpoint='/api/actions/delete-pod';body.pod=name;}
    if(action==='setImage'){endpoint='/api/actions/set-image';body.deployment=name;body.container=$('cmdContainer').value;body.image=$('cmdImage').value;}
    const result=await api(endpoint,{method:'POST',body:JSON.stringify(body)}); $('commandOutput').textContent=result.output||'Done.'; await refresh();
  } catch(err){$('commandOutput').textContent=`ERROR: ${err.message}`;}
}
async function quickDeploymentAction(action,v){const[namespace,deployment]=v.split('|');$('commandOutput').textContent='Running…';showTab('command');try{const ep=action==='restart'?'/api/actions/restart':'/api/actions/rollout-status';const r=await api(ep,{method:'POST',body:JSON.stringify({namespace,deployment})});$('commandOutput').textContent=r.output||'Done.';await refresh();}catch(e){$('commandOutput').textContent=`ERROR: ${e.message}`;}}
async function quickPodDelete(v){const[namespace,pod]=v.split('|');showTab('command');if(!confirm(`Delete pod ${namespace}/${pod}? A controller may recreate it.`))return;try{const r=await api('/api/actions/delete-pod',{method:'POST',body:JSON.stringify({namespace,pod})});$('commandOutput').textContent=r.output||'Done.';await refresh();}catch(e){$('commandOutput').textContent=`ERROR: ${e.message}`;}}

function checkCompatibility() {
  const server=k8sVersion($('checkServer').value),kubectlV=k8sVersion($('checkKubectl').value),kubelet=k8sVersion($('checkKubelet').value); const helmKey=String($('checkHelm').value).match(/(\d+\.\d+)/)?.[1]; const results=[];
  if(!server) results.push(['bad','API server version could not be read.']);
  if(server&&kubectlV){const diff=Math.abs(server.minor-kubectlV.minor);results.push([diff<=1?'good':'bad',`kubectl ${kubectlV.text} is ${diff<=1?'within':'outside'} the supported ±1 minor skew from API server ${server.text}.`]);}
  if(server&&kubelet){const ok=kubelet.minor<=server.minor&&kubelet.minor>=server.minor-3;results.push([ok?'good':'bad',`kubelet ${kubelet.text} ${ok?'fits':'does not fit'} the rule: not newer than API server and no more than 3 minor versions older.`]);}
  if(server&&helmKey){const r=helmRanges[helmKey]; if(r){const ok=server.minor>=r[0]&&server.minor<=r[1];results.push([ok?'good':'bad',`Helm ${helmKey}.x supports Kubernetes 1.${r[1]} through 1.${r[0]} in the current Helm support table.`]);}else results.push(['warn',`No built-in Helm range for ${helmKey}. Check the official Helm support table.`]);}
  $('compatResults').innerHTML=results.map(([level,msg])=>`<div class="rounded-lg border p-3 text-sm ${level==='good'?'border-emerald-200 bg-emerald-50 dark:border-emerald-900 dark:bg-emerald-950/40':level==='bad'?'border-red-200 bg-red-50 dark:border-red-900 dark:bg-red-950/40':'border-amber-200 bg-amber-50 dark:border-amber-900 dark:bg-amber-950/40'}">${escapeHtml(msg)}</div>`).join('');
}
function checkManifest() {
  const yaml=$('manifestCheckText').value; const t=k8sVersion($('manifestTarget').value); const issues=[];
  const rules=[
    [/apiVersion:\s*extensions\/v1beta1/i,22,'extensions/v1beta1 APIs such as Ingress were removed by Kubernetes 1.22.'],
    [/apiVersion:\s*networking\.k8s\.io\/v1beta1/i,22,'networking.k8s.io/v1beta1 Ingress was removed by Kubernetes 1.22; use networking.k8s.io/v1.'],
    [/apiVersion:\s*apps\/v1beta(1|2)/i,16,'apps/v1beta1 and apps/v1beta2 workload APIs were removed by Kubernetes 1.16; use apps/v1.'],
    [/apiVersion:\s*policy\/v1beta1/i,25,'policy/v1beta1 PodDisruptionBudget was removed by Kubernetes 1.25; use policy/v1.'],
    [/apiVersion:\s*batch\/v1beta1/i,25,'batch/v1beta1 CronJob was removed by Kubernetes 1.25; use batch/v1.'],
    [/apiVersion:\s*autoscaling\/v2beta1/i,25,'autoscaling/v2beta1 HPA was removed by Kubernetes 1.25; use autoscaling/v2.'],
    [/apiVersion:\s*autoscaling\/v2beta2/i,26,'autoscaling/v2beta2 HPA was removed by Kubernetes 1.26; use autoscaling/v2.'],
  ];
  if(!t) issues.push('Target version is invalid.'); else rules.forEach(([re,removed,msg])=>{if(t.minor>=removed&&re.test(yaml))issues.push(msg)});
  $('manifestResults').innerHTML=issues.length?issues.map(i=>`<div class="rounded border border-red-200 bg-red-50 p-3 text-sm dark:border-red-900 dark:bg-red-950/40">${escapeHtml(i)}</div>`).join(''):`<div class="rounded border border-emerald-200 bg-emerald-50 p-3 text-sm dark:border-emerald-900 dark:bg-emerald-950/40">No known removed APIs matched this small built-in rule set. Still run server-side dry-run and your provider’s upgrade checks.</div>`;
}
function renderProviderVersions() {$('providerVersions').innerHTML=providerVersionData.map(p=>`<a class="rounded-lg border border-slate-200 p-3 hover:border-ibmblue-500 dark:border-slate-700" href="${p.url}" target="_blank" rel="noreferrer"><div class="font-semibold">${escapeHtml(p.name)}</div><div class="mt-1 text-sm">${escapeHtml(p.current)}</div><div class="mt-1 text-xs text-slate-500">${escapeHtml(p.note)}</div></a>`).join('');}
function renderUpgradeSteps() {
  const steps=[
    ['1. Inventory','Record cluster version, node versions, kubectl, Helm, CNI/CSI, ingress, operators, CRDs, admission webhooks, and cloud add-ons.'],
    ['2. Read provider notes','Check the exact provider release notes, supported versions, maintenance windows, and breaking changes.'],
    ['3. Patch current minor','Move to the newest patch of your current minor before the next minor upgrade.'],
    ['4. Scan APIs','Find removed/deprecated APIs in YAML, Helm charts, CRDs, and webhook configurations.'],
    ['5. Back up what matters','Back up application data and configuration. For self-managed control planes, include etcd backup procedures.'],
    ['6. Test somewhere safe','Rehearse in a dev/staging cluster with representative workloads and traffic.'],
    ['7. Upgrade control plane','For managed services, follow the provider’s control-plane upgrade workflow. Do not skip minor versions.'],
    ['8. Upgrade nodes/add-ons','Upgrade node pools and critical add-ons in the provider-supported order; drain nodes where required.'],
    ['9. Validate','Check nodes, pods, deployments, services, ingress, DNS, storage, logs, metrics, jobs, autoscaling, and application smoke tests.'],
    ['10. Watch after change','Monitor Warning events, error rates, latency, restarts, unavailable replicas, and cloud/provider health notices.'],
  ];
  $('upgradeSteps').innerHTML=steps.map(([h,b])=>`<div class="rounded-lg border border-slate-200 p-4 dark:border-slate-700"><div class="font-semibold">${h}</div><div class="mt-1 text-sm text-slate-600 dark:text-slate-300">${b}</div></div>`).join('');
}
function renderHelmExamples() {
  const keycloak = [
    ['Install local Keycloak', `./helm-examples/keycloak/install-local.sh`],
    ['Watch the pods', `kubectl get pods,svc -n keycloak -w`],
    ['Reach the admin console', `kubectl -n keycloak port-forward svc/keycloak 8080:80`],
    ['Create demo realm + OIDC client', `KEYCLOAK_ADMIN_PASSWORD='change-me-now' ./helm-examples/keycloak/configure-demo-realm.sh`],
    ['Inspect Helm release', `helm status keycloak -n keycloak\nhelm get values keycloak -n keycloak\nhelm history keycloak -n keycloak`],
    ['Preview a chart upgrade', `helm show chart oci://registry-1.docker.io/bitnamicharts/keycloak\nhelm show values oci://registry-1.docker.io/bitnamicharts/keycloak > /tmp/keycloak-values.yaml`],
  ];
  const oidc = [
    ['Install demo web app', `helm upgrade --install oidc-webapp ./helm-examples/oidc-webapp --namespace oidc-demo --create-namespace`],
    ['Reach the web app', `kubectl -n oidc-demo port-forward svc/oidc-webapp 8088:80`],
    ['Open the app', `http://localhost:8088/`],
    ['Render chart without installing', `helm template oidc-webapp ./helm-examples/oidc-webapp`],
    ['Use real HTTPS names', `helm upgrade --install oidc-webapp ./helm-examples/oidc-webapp \\n  -n oidc-demo --create-namespace \\n  --set oidc.issuer=https://keycloak.example.com/realms/apps \\n  --set oidc.clientId=my-webapp \\n  --set oidc.redirectUri=https://app.example.com/ \\n  --set oidc.postLogoutRedirectUri=https://app.example.com/`],
  ];
  const render = rows => rows.map(([title,cmd]) => `<div class="rounded-lg border border-slate-200 p-3 dark:border-slate-700"><div class="flex items-center justify-between gap-3"><strong>${escapeHtml(title)}</strong><button class="link-btn" data-copy="${escapeHtml(cmd)}">Copy</button></div><pre class="mono mt-2 whitespace-pre-wrap overflow-auto rounded bg-slate-950 p-3 text-xs text-slate-100">${escapeHtml(cmd)}</pre></div>`).join('');
  $('keycloakHelmExamples').innerHTML = render(keycloak);
  $('oidcHelmExamples').innerHTML = render(oidc);
  bindCopyButtons();
}

function renderLearn() {
  const cards=[
    ['Cluster','A school campus. It contains the machines and the Kubernetes control system.'],['Control plane','The school office. It keeps the master record of what should be running and tells workers what to do.'],['Node','A classroom building/computer where workloads can run.'],['Pod','A lunchbox holding one or more closely related containers. Kubernetes schedules the whole lunchbox together.'],['Deployment','A teacher’s instruction: “Keep 3 copies of this app running.” If one disappears, Kubernetes makes another.'],['Service','The school’s main phone number for a group of pods. Pods can come and go, but the Service gives a stable way to reach them.'],['Namespace','A labeled section of the school, like Grade 6 or Grade 7, used to organize and separate resources.'],['Helm','A recipe/package system for Kubernetes. A chart is a reusable recipe for installing many related YAML resources.'],['kubectl','The command-line remote control. It sends requests to the Kubernetes API server.'],['Kubeconfig','The address book and ID badge information kubectl uses to know which cluster and identity to use.'],['Event','A short note from Kubernetes about something that happened, such as a failed image pull or scheduling problem.'],['Logs','The running app’s diary. Logs help explain what the process did and why it failed.'],
  ];
  $('learnCards').innerHTML=cards.map(([h,b])=>`<div class="rounded-lg border border-slate-200 p-4 dark:border-slate-700"><div class="font-semibold">${h}</div><div class="mt-1 text-sm text-slate-600 dark:text-slate-300">${b}</div></div>`).join('');
  $('referenceLinks').innerHTML=refs.map(([name,url])=>`<a class="rounded border border-slate-200 p-3 text-sm font-semibold text-ibmblue-600 hover:border-ibmblue-500 dark:border-slate-700 dark:text-blue-300" href="${url}" target="_blank" rel="noreferrer">${escapeHtml(name)} ↗</a>`).join('');
}
function bindCopyButtons(){document.querySelectorAll('[data-copy]').forEach(b=>{if(b.dataset.bound)return;b.dataset.bound='1';b.addEventListener('click',async()=>{try{await navigator.clipboard.writeText(b.dataset.copy);const old=b.textContent;b.textContent='Copied';setTimeout(()=>b.textContent=old,900);}catch{}})});}

async function applyOrDiff(mode){const manifest=$('applyYaml').value,namespace=state.namespace==='all'?'default':state.namespace;$('applyOutput').textContent=`Running kubectl ${mode}…`;try{const r=await api(`/api/actions/${mode}`,{method:'POST',body:JSON.stringify({namespace,manifest})});$('applyOutput').textContent=r.output||'Done.';if(mode==='apply')await refresh();}catch(e){$('applyOutput').textContent=`ERROR: ${e.message}`;}}

function initThemeFont(){const savedTheme=localStorage.getItem('kcd.theme');const dark=savedTheme?savedTheme==='dark':matchMedia('(prefers-color-scheme: dark)').matches;document.documentElement.classList.toggle('dark',dark);state.fontSize=Math.max(14,Math.min(36,state.fontSize));document.documentElement.style.setProperty('--base-font',`${state.fontSize}px`);$('fontSizeLabel').textContent=`${state.fontSize}px`;}
function changeFont(delta){state.fontSize=Math.max(14,Math.min(36,state.fontSize+delta));localStorage.setItem('kcd.fontSize',state.fontSize);document.documentElement.style.setProperty('--base-font',`${state.fontSize}px`);$('fontSizeLabel').textContent=`${state.fontSize}px`;}

function setAutoRefresh(seconds) {
  state.autoRefreshSeconds = Number(seconds) || 0;
  localStorage.setItem('kcd.autoRefresh', String(state.autoRefreshSeconds));
  if (state.autoRefreshTimer) clearInterval(state.autoRefreshTimer);
  state.autoRefreshTimer = null;
  if (state.autoRefreshSeconds > 0) {
    state.autoRefreshTimer = setInterval(() => refresh(), state.autoRefreshSeconds * 1000);
  }
}

function bindEvents(){
  $('providerSelect').addEventListener('change',e=>{state.provider=e.target.value;localStorage.setItem('kcd.provider',state.provider);renderProviderHint();});
  $('contextSelect').addEventListener('change',async e=>{try{await api('/api/context',{method:'POST',body:JSON.stringify({context:e.target.value})});await loadContext();await loadNamespaces();await loadHelmVersion();await refresh();}catch(err){alert(err.message);}});
  $('namespaceSelect').addEventListener('change',e=>{state.namespace=e.target.value;localStorage.setItem('kcd.namespace',state.namespace);refresh();});
  $('autoRefresh').value=String(state.autoRefreshSeconds); $('autoRefresh').addEventListener('change',e=>setAutoRefresh(e.target.value));
  $('refreshBtn').addEventListener('click',refresh); $('loadLogsBtn').addEventListener('click',loadLogs); $('clearLogsBtn').addEventListener('click',()=>{$('logOutput').textContent='';});
  $('commandAction').addEventListener('change',renderCommands); $('runCommandBtn').addEventListener('click',runCommand);
  $('checkVersionsBtn').addEventListener('click',checkCompatibility); $('checkManifestBtn').addEventListener('click',checkManifest);
  $('fontDown').addEventListener('click',()=>changeFont(-1));$('fontUp').addEventListener('click',()=>changeFont(1));
  $('themeToggle').addEventListener('click',()=>{const dark=!document.documentElement.classList.contains('dark');document.documentElement.classList.toggle('dark',dark);localStorage.setItem('kcd.theme',dark?'dark':'light');});
  document.querySelectorAll('[data-open-dialog]').forEach(b=>b.addEventListener('click',()=>$(b.dataset.openDialog).showModal()));
  $('openApplyBtn').addEventListener('click',()=> $('applyDialog').showModal()); $('diffYamlBtn').addEventListener('click',()=>applyOrDiff('diff')); $('applyYamlBtn').addEventListener('click',()=>applyOrDiff('apply'));
}

async function boot(){injectUtilityClasses();initThemeFont();renderProviders();renderTabs();renderProviderVersions();renderUpgradeSteps();renderHelmExamples();renderLearn();bindEvents();setAutoRefresh(state.autoRefreshSeconds);checkCompatibility();await loadContext();await loadNamespaces();await loadHelmVersion();await refresh();}
boot();
