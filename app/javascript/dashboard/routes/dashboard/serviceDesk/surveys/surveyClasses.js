import { normalizeClass } from 'vue';

// Tailwind utilities grouped by the editor's semantic hooks. No stylesheet or global resets.
const styles = {
  'sv-manager':
    '[font-family:inherit] [color:#172b4d] [font-size:14px] [line-height:1.5] [&_*]:[box-sizing:border-box] [&_button]:[font-family:inherit] [&_button]:[cursor:pointer] [&_button:disabled]:[opacity:.5] [&_button:disabled]:[cursor:not-allowed] [&_h2]:[font-size:24px] [&_h2]:[margin:6px_0] [&_h2]:[color:#092e52] [&_h2]:[font-weight:700] [&_p]:[margin:6px_0] [&_p]:[color:#65758d] [@media(max-width:720px)]:[&_h2]:[font-size:21px]',
  'sv-modal':
    '[font-family:inherit] [color:#172b4d] [font-size:14px] [line-height:1.5] [&_*]:[box-sizing:border-box] [&_button]:[font-family:inherit] [&_button]:[cursor:pointer] [&_button:disabled]:[opacity:.5] [&_button:disabled]:[cursor:not-allowed] [width:min(1160px,100%)] [height:min(860px,calc(100dvh_-_44px))] [max-height:calc(100dvh_-_44px)] [display:flex] [flex-direction:column] [background:#fff] [border-radius:17px] [overflow:hidden] [box-shadow:0_30px_95px_#00132966] [outline:none] [position:relative] [@media(min-width:1500px)]:[height:min(900px,calc(100dvh_-_60px))] [@media(max-width:720px)]:[height:calc(100dvh_-_16px)] [@media(max-width:720px)]:[max-height:calc(100dvh_-_16px)] [@media(max-width:720px)]:[border-radius:12px]',
  'sv-small-dialog':
    '[font-family:inherit] [color:#172b4d] [font-size:14px] [line-height:1.5] [&_*]:[box-sizing:border-box] [&_button]:[font-family:inherit] [&_button]:[cursor:pointer] [&_button:disabled]:[opacity:.5] [&_button:disabled]:[cursor:not-allowed] [&_label]:[display:grid] [&_label]:[gap:6px] [&_label]:[font-size:12px] [&_label]:[color:#3c4c66] [&_label]:[font-weight:600] [&_label_small]:[font-size:11px] [&_label_small]:[color:#72839b] [&_label_small]:[font-weight:400] [&_label_small]:[line-height:1.6] [&_input]:[font-family:inherit] [&_input]:[color:#263e5c] [&_input]:[background:white] [&_input]:[border:1px_solid_#d8e0ed] [&_input]:[border-radius:7px] [&_input]:[padding:9px_11px] [&_input]:[font-size:12px] [&_input]:[width:100%] [&_input]:[min-width:0] [&_input]:[outline:none] [&_input]:[min-height:38px] [&_input:focus]:[border-color:#6c9ef7] [&_input:focus]:[box-shadow:0_0_0_3px_#e8f1ff] [background:white] [border-radius:13px] [box-shadow:0_10px_50px_#12334b33] [padding:24px] [width:min(530px,100%)] [max-height:90dvh] [overflow:auto] [&_h3]:[font-size:18px] [&_h3]:[color:#163958] [&_h3]:[margin:0_0_12px] [&_h3]:[font-weight:700] [&_p]:[font-size:13px] [&_p]:[line-height:1.7] [&_p]:[color:#687b93] [&_footer]:[display:flex] [&_footer]:[gap:8px] [&_footer]:[justify-content:flex-end] [&_footer]:[flex-wrap:wrap] [&_footer]:[margin-top:20px]',
  'sv-manager-header':
    '[display:flex] [justify-content:space-between] [align-items:center] [gap:20px] [padding:22px_24px] [background:linear-gradient(120deg,#f1f7ff,#faf5ff)] [border:1px_solid_#e2e8f3] [border-radius:16px] [margin-bottom:20px] [@media(max-width:720px)]:[padding:16px] [@media(max-width:720px)]:[flex-direction:column] [@media(max-width:720px)]:[align-items:flex-start]',
  'sv-eyebrow':
    '[font-size:10px] [font-weight:700] [letter-spacing:.08em] [color:#557096]',
  'sv-button':
    '[display:inline-flex] [justify-content:center] [align-items:center] [gap:8px] [padding:9px_15px] [border:1px_solid_#cdd9e8] [background:#fff] [border-radius:8px] [color:#164a80] [font-weight:600] [font-size:12px] [white-space:nowrap] [min-height:38px] [transition:box-shadow_.15s] [&:hover:not(:disabled)]:[box-shadow:0_0_0_3px_#e9f2ff]',
  'sv-primary':
    '[background:linear-gradient(110deg,#0069ec,#5345ea_75%,#8c3eea)] [color:#fff] [border-color:transparent] [box-shadow:0_3px_9px_#3456cc22]',
  'sv-text-button':
    '[color:#0869d7] [background:none] [border:none] [padding:3px] [font-size:12px] [font-weight:600]',
  'sv-stat-row':
    '[display:grid] [grid-template-columns:repeat(3,1fr)] [gap:12px] [margin:16px_0] [&_article]:[display:flex] [&_article]:[flex-direction:column] [&_article]:[padding:18px] [&_article]:[border-radius:12px] [&_strong]:[font-size:20px] [&_strong]:[color:#173958] [&_span]:[font-size:12px] [&_span]:[margin-top:6px] [@media(max-width:720px)]:[grid-template-columns:1fr]',
  'sv-tinted':
    '[padding:16px] [border-radius:10px] [border:1px_solid_#dde7f1] [&.purple]:[background:#f3edff] [&.purple]:[border-color:#e6d6ff] [&.purple]:[color:#7044b5] [&.blue]:[background:#eaf4ff] [&.blue]:[border-color:#cfe4ff] [&.blue]:[color:#2164a8] [&.green]:[background:#e8faf3] [&.green]:[border-color:#c9eee0] [&.green]:[color:#15795a] [&.amber]:[background:#fff7e8] [&.amber]:[border-color:#f4e5be] [&.amber]:[color:#8c601b] [&.pink]:[background:#fff0f6] [&.pink]:[border-color:#f5d1e2] [&.pink]:[color:#a73f70]',
  'sv-section-icon':
    '[&.purple]:[background:#f3edff] [&.purple]:[border-color:#e6d6ff] [&.purple]:[color:#7044b5] [&.blue]:[background:#eaf4ff] [&.blue]:[border-color:#cfe4ff] [&.blue]:[color:#2164a8] [&.green]:[background:#e8faf3] [&.green]:[border-color:#c9eee0] [&.green]:[color:#15795a] [&.amber]:[background:#fff7e8] [&.amber]:[border-color:#f4e5be] [&.amber]:[color:#8c601b] [&.pink]:[background:#fff0f6] [&.pink]:[border-color:#f5d1e2] [&.pink]:[color:#a73f70] [display:grid] [place-items:center] [border:1px_solid_#dbe6f5] [border-radius:9px] [width:36px] [height:36px] [font-size:18px] [flex-shrink:0]',
  'sv-question-number':
    '[&.purple]:[background:#f3edff] [&.purple]:[border-color:#e6d6ff] [&.purple]:[color:#7044b5] [&.blue]:[background:#eaf4ff] [&.blue]:[border-color:#cfe4ff] [&.blue]:[color:#2164a8] [&.green]:[background:#e8faf3] [&.green]:[border-color:#c9eee0] [&.green]:[color:#15795a] [&.amber]:[background:#fff7e8] [&.amber]:[border-color:#f4e5be] [&.amber]:[color:#8c601b] [display:grid] [place-items:center] [align-self:stretch] [min-height:55px] [min-width:35px] [border-radius:7px] [font-size:19px] [font-weight:700]',
  'sv-sharing-card':
    '[&.purple]:[background:#f3edff] [&.purple]:[border-color:#e6d6ff] [&.purple]:[color:#7044b5] [&.blue]:[background:#eaf4ff] [&.blue]:[border-color:#cfe4ff] [&.blue]:[color:#2164a8] [&.green]:[background:#e8faf3] [&.green]:[border-color:#c9eee0] [&.green]:[color:#15795a] [display:grid] [grid-template-columns:auto_1fr] [gap:5px_9px] [padding:15px] [border:1px_solid_#dce7f1] [border-radius:10px] [align-items:center] [&_strong]:[font-size:13px] [&_small]:[grid-column:2] [&_small]:[font-size:11px]',
  'sv-empty':
    '[text-align:center] [padding:46px_24px] [border:1px_dashed_#d7e0ed] [background:white] [border-radius:14px] [&_h3]:[font-size:18px] [&_h3]:[margin:12px] [&_p]:[max-width:550px] [&_p]:[margin:12px_auto_22px]',
  'sv-empty-icon': '[font-size:40px] [color:#7956d9]',
  'sv-model-grid':
    '[display:grid] [grid-template-columns:repeat(auto-fit,minmax(280px,1fr))] [gap:16px] [@media(max-width:720px)]:[grid-template-columns:1fr]',
  'sv-model-card':
    '[border:1px_solid_#e0e7f0] [border-radius:14px] [padding:19px] [background:#fff] [min-width:0] [box-shadow:0_2px_4px_#173b6010] [&_header]:[display:flex] [&_header]:[align-items:center] [&_header]:[gap:10px] [&_header]:[justify-content:space-between] [&_footer]:[display:flex] [&_footer]:[align-items:center] [&_footer]:[gap:10px] [&_footer]:[justify-content:space-between] [&_h3]:[font-weight:700] [&_h3]:[font-size:17px] [&_h3]:[margin:18px_0_6px] [&_h3]:[overflow-wrap:anywhere] [&>p]:[min-height:44px] [&>p]:[font-size:12px] [&>p]:[overflow-wrap:anywhere] [&_footer]:[border-top:1px_solid_#edf0f6] [&_footer]:[padding-top:13px] [&_footer]:[flex-wrap:wrap] [&_details]:[position:relative] [&_details]:[font-size:12px] [&_details_button]:[display:block] [&_details_button]:[padding:8px] [&_details_button]:[border:none] [&_details_button]:[background:#eff5ff] [&_details_button]:[width:100%] [&_details_button]:[text-align:left] [&_details_button]:[margin-top:3px]',
  'sv-kind-badge':
    '[padding:4px_8px] [border-radius:6px] [font-size:10px] [font-weight:700] [&.nps]:[background:#f0e6ff] [&.nps]:[color:#7132af] [&.csat]:[background:#fff1c9] [&.csat]:[color:#946409] [&.ces]:[background:#ffe9f2] [&.ces]:[color:#a53161]',
  'sv-status':
    '[padding:4px_8px] [border-radius:6px] [font-size:10px] [font-weight:700] [&.green]:[background:#dbf5e9] [&.green]:[color:#14704b] [&.blue]:[background:#e7f2ff] [&.blue]:[color:#1c62a3] [&.amber]:[background:#fff1dc] [&.amber]:[color:#895b17]',
  'sv-model-meta':
    '[display:flex] [flex-wrap:wrap] [gap:8px_15px] [padding:16px_0] [color:#68788e] [font-size:11px] [&_small]:[width:100%] [&_small]:[font-family:monospace]',
  'sv-pagination':
    '[display:flex] [justify-content:center] [gap:22px] [align-items:center] [padding:20px]',
  'sv-overlay':
    '[position:fixed] [inset:0] [z-index:10020] [background:#061e3d88] [backdrop-filter:blur(3px)] [display:flex] [align-items:center] [justify-content:center] [padding:22px] [@media(max-width:720px)]:[padding:8px]',
  'sv-modal-header':
    '[display:flex] [justify-content:space-between] [align-items:center] [gap:16px] [padding:21px_25px] [background:linear-gradient(105deg,#eaf4ff_0%,#f5edff_52%,#fcecf9_100%)] [border-bottom:1px_solid_#e2dff4] [flex-shrink:0] [&_h2]:[margin:0] [&_h2]:[font-size:21px] [&_h2]:[font-weight:750] [&_h2]:[letter-spacing:-.02em] [&_h2]:[color:#123558] [&_p]:[margin:3px_0_0] [&_p]:[font-size:12px] [&_p]:[color:#69748d] [@media(max-width:720px)]:[padding:15px] [@media(max-width:720px)]:[gap:8px] [@media(max-width:720px)]:[&_h2]:[font-size:17px] [@media(max-width:720px)]:[&_p]:[font-size:10px] [&>div:nth-child(2)]:[flex:1] [&>div:nth-child(2)]:[min-width:0] [@media(max-width:720px)]:[&_.sv-eyebrow]:[font-size:8px]',
  'sv-title-block': '[display:flex] [gap:14px] [align-items:center]',
  'sv-title-icon':
    '[width:46px] [height:46px] [border-radius:12px] [background:linear-gradient(145deg,#cee5ff,#ebd6ff)] [display:grid] [place-items:center] [color:#5262d9] [font-size:25px] [flex-shrink:0] [@media(max-width:720px)]:[width:37px] [@media(max-width:720px)]:[height:37px] [@media(max-width:720px)]:[font-size:20px]',
  'sv-icon-button':
    '[width:32px] [height:32px] [display:grid] [place-items:center] [background:transparent] [border:none] [border-radius:7px] [color:#586987] [font-size:18px] [&:hover]:[background:#ffffffaa]',
  'sv-stepper':
    '[display:grid] [grid-template-columns:repeat(6,minmax(0,1fr))] [gap:4px] [list-style:none] [padding:16px_22px] [margin:0] [border-bottom:1px_solid_#edf0f6] [background:#fff] [flex-shrink:0] [&_button]:[display:flex] [&_button]:[width:100%] [&_button]:[align-items:center] [&_button]:[justify-content:center] [&_button]:[gap:7px] [&_button]:[padding:9px_4px] [&_button]:[background:none] [&_button]:[border:none] [&_button]:[border-radius:9px] [&_button]:[font-size:11px] [&_button]:[color:#768096] [&_button]:[min-width:0] [&_button>span:first-child]:[width:24px] [&_button>span:first-child]:[height:24px] [&_button>span:first-child]:[border:1.5px_solid_#cec4e4] [&_button>span:first-child]:[border-radius:50%] [&_button>span:first-child]:[display:grid] [&_button>span:first-child]:[place-items:center] [&_button>span:first-child]:[font-size:11px] [&_button>span:first-child]:[font-weight:700] [&_button>span:first-child]:[flex-shrink:0] [&_.active]:[background:#eaf3ff] [&_.active]:[color:#0862d2] [&_.active]:[font-weight:700] [&_.active>span:first-child]:[background:#0879ef] [&_.active>span:first-child]:[border-color:#0879ef] [&_.active>span:first-child]:[color:#fff] [&_.completed]:[color:#1a9472] [&_.completed>span:first-child]:[background:#e2f8ed] [&_.completed>span:first-child]:[border-color:#a5dfc5] [&_.completed>span:first-child]:[color:#187e5a] [@media(min-width:721px)_and_(max-width:950px)]:[padding:12px] [@media(min-width:721px)_and_(max-width:950px)]:[&_button]:[font-size:10px] [@media(min-width:721px)_and_(max-width:950px)]:[&_button]:[gap:4px] [@media(max-width:720px)]:[grid-template-columns:repeat(3,1fr)] [@media(max-width:720px)]:[padding:8px] [@media(max-width:720px)]:[gap:3px] [@media(max-width:720px)]:[&_button]:[padding:6px_2px] [@media(max-width:720px)]:[&_button]:[justify-content:flex-start] [@media(max-width:720px)]:[&_button]:[font-size:10px] [@media(max-width:720px)]:[&_button>span:first-child]:[width:20px] [@media(max-width:720px)]:[&_button>span:first-child]:[height:20px] [&_.current]:[background:#eaf3ff] [&_.current]:[color:#0862d2] [&_.current]:[font-weight:700] [&_.current>span:first-child]:[background:#0879ef] [&_.current>span:first-child]:[border-color:#0879ef] [&_.current>span:first-child]:[color:#fff] [&_.done]:[color:#1a9472] [&_.done>span:first-child]:[background:#e2f8ed] [&_.done>span:first-child]:[border-color:#a5dfc5] [&_.done>span:first-child]:[color:#187e5a]',
  'sv-modal-body':
    '[overflow-y:auto] [padding:20px_24px_24px] [flex:1] [min-height:0] [overscroll-behavior:contain] [@media(min-width:721px)_and_(max-width:950px)]:[padding:16px]',
  'sv-body-grid':
    '[display:grid] [grid-template-columns:minmax(0,1fr)_300px] [gap:24px] [align-items:start] [@media(min-width:721px)_and_(max-width:950px)]:[grid-template-columns:minmax(0,1fr)_250px] [@media(min-width:721px)_and_(max-width:950px)]:[gap:16px] [@media(max-width:720px)]:[grid-template-columns:1fr]',
  'sv-main-section': '[border:0] [padding:0] [margin:0] [min-width:0]',
  'sv-step-heading':
    '[display:flex] [align-items:center] [gap:10px] [margin-bottom:17px] [outline:none] [&_h3]:[font-size:17px] [&_h3]:[color:#153759] [&_h3]:[font-weight:700] [&_h3]:[margin:0] [&_p]:[font-size:11px] [&_p]:[color:#8190a7] [&_p]:[margin:3px_0_0]',
  'sv-fields':
    "[display:grid] [gap:17px] [min-width:0] [&_label]:[display:grid] [&_label]:[gap:6px] [&_label]:[font-size:12px] [&_label]:[color:#3c4c66] [&_label]:[font-weight:600] [&_label_small]:[font-size:11px] [&_label_small]:[color:#72839b] [&_label_small]:[font-weight:400] [&_label_small]:[line-height:1.6] [&_input:not([type=checkbox]):not([type=radio])]:[font-family:inherit] [&_input:not([type=checkbox]):not([type=radio])]:[color:#263e5c] [&_input:not([type=checkbox]):not([type=radio])]:[background:white] [&_input:not([type=checkbox]):not([type=radio])]:[border:1px_solid_#d8e0ed] [&_input:not([type=checkbox]):not([type=radio])]:[border-radius:7px] [&_input:not([type=checkbox]):not([type=radio])]:[padding:9px_11px] [&_input:not([type=checkbox]):not([type=radio])]:[font-size:12px] [&_input:not([type=checkbox]):not([type=radio])]:[width:100%] [&_input:not([type=checkbox]):not([type=radio])]:[min-width:0] [&_input:not([type=checkbox]):not([type=radio])]:[outline:none] [&_input:not([type=checkbox]):not([type=radio])]:[min-height:38px] [&_select]:[font-family:inherit] [&_select]:[color:#263e5c] [&_select]:[background:white] [&_select]:[border:1px_solid_#d8e0ed] [&_select]:[border-radius:7px] [&_select]:[padding:9px_11px] [&_select]:[font-size:12px] [&_select]:[width:100%] [&_select]:[min-width:0] [&_select]:[outline:none] [&_select]:[min-height:38px] [&_textarea]:[font-family:inherit] [&_textarea]:[color:#263e5c] [&_textarea]:[background:white] [&_textarea]:[border:1px_solid_#d8e0ed] [&_textarea]:[border-radius:7px] [&_textarea]:[padding:9px_11px] [&_textarea]:[font-size:12px] [&_textarea]:[width:100%] [&_textarea]:[min-width:0] [&_textarea]:[outline:none] [&_textarea]:[min-height:38px] [&_input:focus]:[border-color:#6c9ef7] [&_input:focus]:[box-shadow:0_0_0_3px_#e8f1ff] [&_select:focus]:[border-color:#6c9ef7] [&_select:focus]:[box-shadow:0_0_0_3px_#e8f1ff] [&_textarea:focus]:[border-color:#6c9ef7] [&_textarea:focus]:[box-shadow:0_0_0_3px_#e8f1ff] [&_input:disabled]:[background:#f2f5f9] [&_input:disabled]:[color:#65758c] [&_select:disabled]:[background:#f2f5f9] [&_select:disabled]:[color:#65758c] [&_textarea]:[resize:vertical] [&_textarea]:[min-height:84px] [&_h4]:[font-size:13px] [&_h4]:[color:#203b5e] [&_h4]:[font-weight:700] [&_h4]:[margin:0_0_8px] [&_p]:[margin:5px_0] [&_p]:[font-size:12px] [&_input[type=checkbox]]:[width:16px] [&_input[type=checkbox]]:[height:16px] [&_input[type=checkbox]]:[accent-color:#086fef] [&_input[type=checkbox]]:[flex-shrink:0] [&_input[type=checkbox]]:[margin:0] [&_input[type=radio]]:[width:16px] [&_input[type=radio]]:[height:16px] [&_input[type=radio]]:[accent-color:#086fef] [&_input[type=radio]]:[flex-shrink:0] [&_input[type=radio]]:[margin:0] [&_input[role=switch]]:[width:32px] [&_input[role=switch]]:[height:18px] [&_input[role=switch]]:[appearance:none] [&_input[role=switch]]:[background:#bfcbdc] [&_input[role=switch]]:[border-radius:12px] [&_input[role=switch]]:[position:relative] [&_input[role=switch]]:[transition:background_.15s] [&_input[role=switch]]:[border:1px_solid_transparent] [&_input[role=switch]::after]:[content:''] [&_input[role=switch]::after]:[position:absolute] [&_input[role=switch]::after]:[width:12px] [&_input[role=switch]::after]:[height:12px] [&_input[role=switch]::after]:[background:white] [&_input[role=switch]::after]:[border-radius:50%] [&_input[role=switch]::after]:[left:2px] [&_input[role=switch]::after]:[top:2px] [&_input[role=switch]::after]:[box-shadow:0_1px_3px_#384f7960] [&_input[role=switch]:checked]:[background:#0876ec] [&_input[role=switch]:checked::after]:[left:16px] [&_label.sv-check-row]:[display:flex] [&_label.sv-check-row]:[gap:9px] [&_label.sv-check-row]:[align-items:center] [&_label.sv-check-row]:[font-weight:400] [&_label.sv-check-row]:[line-height:1.5] [&_label.sv-radio-row]:[display:flex] [&_label.sv-radio-row]:[gap:9px] [&_label.sv-radio-row]:[align-items:center] [&_label.sv-radio-row]:[font-weight:400] [&_label.sv-radio-row]:[line-height:1.5] [@media(max-width:720px)]:[&_label]:[font-size:11px]",
  'sv-help':
    '[font-size:11px] [color:#72839b] [font-weight:400] [line-height:1.6]',
  'sv-check-row':
    '[display:flex] [gap:9px] [align-items:center] [font-weight:400] [line-height:1.5]',
  'sv-radio-row': '[margin:10px_0]',
  'sv-required': '[color:#d13e67]',
  'sv-two':
    '[display:grid] [grid-template-columns:1fr_1fr] [gap:14px] [@media(max-width:720px)]:[gap:10px]',
  'sv-kind-grid':
    '[display:grid] [grid-template-columns:repeat(3,1fr)] [gap:10px] [@media(max-width:720px)]:[gap:5px]',
  'sv-kind-option':
    '[padding:15px_12px] [display:flex] [align-items:flex-start] [gap:8px] [border:1px_solid_#dee5ef] [border-radius:10px] [background:white] [text-align:left] [color:#536680] [&>span:first-child]:[font-size:21px] [&_strong]:[font-size:13px] [&_strong]:[color:#283e59] [&_strong]:[display:block] [&_small]:[display:block] [&_small]:[font-size:10px] [&_small]:[margin-top:5px] [&.nps]:[background:#faf6ff] [&.csat]:[background:#fffbeb] [&.ces]:[background:#fff5f9] [&.selected]:[border:2px_solid_#8662db] [&.selected]:[box-shadow:0_0_0_2px_#eee6fb] [&.selected]:[padding:14px_11px] [@media(max-width:720px)]:[padding:11px_6px] [@media(max-width:720px)]:[gap:5px] [@media(max-width:720px)]:[&.selected]:[padding:10px_5px] [@media(max-width:720px)]:[&_small]:[font-size:9px]',
  'sv-question-toolbar':
    '[display:flex] [gap:9px] [justify-content:flex-end] [align-items:center] [&_select]:[max-width:160px]',
  'sv-question-card':
    '[border:1px_solid_#e2e6ef] [border-radius:10px] [overflow:hidden] [background:white] [&.editing]:[border-color:#adbef2] [&.editing]:[box-shadow:0_0_0_2px_#f1f4ff] [&>header]:[padding:13px] [&>header]:[display:flex] [&>header]:[gap:10px] [&>header]:[align-items:center] [@media(max-width:720px)]:[&>header]:[padding:10px] [@media(max-width:720px)]:[&>header]:[gap:7px]',
  'sv-question-text':
    '[flex:1] [min-width:0] [&_strong]:[font-size:12px] [&_strong]:[display:block] [&_strong]:[margin:5px_0] [&_strong]:[overflow-wrap:anywhere] [&_strong]:[color:#334866] [&_small]:[font-size:10px] [&_small]:[color:#7b8ca4]',
  'sv-question-tag':
    '[font-size:10px] [display:inline-block] [color:#7554a6] [background:#f2eaff] [border-radius:4px] [padding:2px_5px]',
  'sv-question-actions':
    '[display:flex] [flex-wrap:wrap] [gap:3px] [max-width:92px] [justify-content:flex-end] [&_button]:[border:1px_solid_#e2e8f0] [&_button]:[border-radius:4px] [&_button]:[padding:2px_5px] [&_button]:[font-size:11px] [&_button]:[color:#4d6a8e] [&_button]:[background:#fbfdff]',
  'sv-question-editor':
    '[background:#f8faff] [border-top:1px_solid_#e2e8f6] [padding:16px] [display:grid] [gap:13px]',
  'sv-choice-row':
    '[display:grid] [grid-template-columns:1fr_1.4fr_auto] [gap:8px] [align-items:center] [&_button]:[padding:6px] [&_button]:[border:0] [&_button]:[background:none] [&_button]:[color:#ac4162]',
  'sv-advanced':
    '[border:1px_solid_#e5eaf2] [border-radius:8px] [padding:11px] [font-size:11px] [color:#667b95] [&_summary]:[cursor:pointer] [&_summary]:[font-weight:600] [&>label]:[margin-top:10px] [&>div]:[margin-top:10px]',
  'sv-channel-card':
    '[border:1px_solid_#dce4f0] [border-radius:10px] [overflow:hidden] [background:#fbfdff] [&>header]:[display:flex] [&>header]:[gap:12px] [&>header]:[align-items:center] [&>header]:[padding:15px] [&>header>div]:[flex:1] [&_strong]:[font-size:14px] [&_strong]:[color:#23415c] [&_p]:[font-size:11px] [&_p]:[color:#687b90] [&_p]:[margin:2px_0] [&.enabled.green]:[background:#f0fcf6] [&.enabled.green]:[border-color:#c5ebda] [&.enabled.blue]:[background:#f0f7ff] [&.enabled.blue]:[border-color:#c5dff9] [&.enabled.purple]:[background:#f8f2ff] [&.enabled.purple]:[border-color:#e2cef4] [&.unavailable]:[background:#fff5f8] [&.unavailable]:[opacity:.85] [&.green]:[background:#edfcf5] [&.green]:[border-color:#bfe5d3] [&.blue]:[background:#edf6ff] [&.blue]:[border-color:#c3def8] [&.purple]:[background:#f8f1ff] [&.purple]:[border-color:#e0c8f4] [&.pink]:[background:#fff1f7] [&.pink]:[border-color:#f2d4e4] [&.green_.sv-channel-icon]:[background:#ccf2df] [&.green_.sv-channel-icon]:[color:#078f65] [&.blue_.sv-channel-icon]:[background:#d2e8ff] [&.blue_.sv-channel-icon]:[color:#176ac0]',
  'sv-channel-config':
    '[padding:15px] [border-top:1px_solid_#e1e9f1] [background:#ffffffa6] [display:grid] [gap:12px]',
  'sv-channel-icon':
    '[width:37px] [height:37px] [display:grid] [place-items:center] [font-size:19px] [border-radius:9px] [flex-shrink:0] [background:#eadfff] [color:#8954c6] [&.green]:[background:#d2f3e2] [&.green]:[color:#078f65] [&.blue]:[background:#d9eafe] [&.blue]:[color:#1672cd] [&.pink]:[background:#ffe1ed] [&.pink]:[color:#cf4380]',
  'sv-channel-state':
    '[font-size:10px] [font-weight:700] [border-radius:5px] [padding:3px_7px] [background:#f1e2e8] [color:#9c5272]',
  'sv-day-grid':
    '[display:flex] [flex-wrap:wrap] [gap:6px] [margin:12px_0] [&_button]:[padding:7px_9px] [&_button]:[border:1px_solid_#e4dccb] [&_button]:[background:white] [&_button]:[border-radius:6px] [&_button]:[color:#896d35] [&_button]:[font-size:11px] [&_button.selected]:[background:#0876ec] [&_button.selected]:[color:white] [&_button.selected]:[border-color:#0876ec]',
  'sv-channel-order':
    '[display:flex] [align-items:center] [gap:7px] [&_span]:[flex:1] [&_button]:[background:white] [&_button]:[border:1px_solid_#dce4ef] [&_button]:[border-radius:4px]',
  'sv-team-choices':
    '[display:grid] [gap:8px] [max-height:140px] [overflow:auto] [margin-top:12px]',
  'sv-permissions-table':
    '[overflow:auto] [border:1px_solid_#e0e6f0] [border-radius:9px] [&_table]:[border-collapse:collapse] [&_table]:[min-width:395px] [&_table]:[width:100%] [&_table]:[font-size:11px] [&_th]:[padding:11px] [&_th]:[border-bottom:1px_solid_#e7edf4] [&_th]:[text-align:center] [&_td]:[padding:11px] [&_td]:[border-bottom:1px_solid_#e7edf4] [&_td]:[text-align:center] [&_th:first-child]:[text-align:left] [&_thead]:[background:#f3f7fc] [@media(max-width:500px)]:[overflow:visible] [@media(max-width:500px)]:[&_table]:[display:block] [@media(max-width:500px)]:[&_table]:[width:100%] [@media(max-width:500px)]:[&_table]:[min-width:0] [@media(max-width:500px)]:[&_tbody]:[display:block] [@media(max-width:500px)]:[&_tbody]:[width:100%] [@media(max-width:500px)]:[&_tbody]:[min-width:0] [@media(max-width:500px)]:[&_thead]:[display:none] [@media(max-width:500px)]:[&_tbody_tr]:[display:grid] [@media(max-width:500px)]:[&_tbody_tr]:[grid-template-columns:1fr_1fr] [@media(max-width:500px)]:[&_tbody_tr]:[border:1px_solid_#dce6f2] [@media(max-width:500px)]:[&_tbody_tr]:[border-radius:9px] [@media(max-width:500px)]:[&_tbody_tr]:[overflow:hidden] [@media(max-width:500px)]:[&_tbody_tr]:[margin-bottom:9px] [@media(max-width:500px)]:[&_tbody_th]:[grid-column:1/-1] [@media(max-width:500px)]:[&_tbody_th]:[background:#eef4fd] [@media(max-width:500px)]:[&_tbody_th]:[padding:10px] [@media(max-width:500px)]:[&_tbody_th]:[text-align:left] [@media(max-width:500px)]:[&_tbody_td]:[display:flex] [@media(max-width:500px)]:[&_tbody_td]:[align-items:center] [@media(max-width:500px)]:[&_tbody_td]:[justify-content:space-between] [@media(max-width:500px)]:[&_tbody_td]:[gap:8px] [@media(max-width:500px)]:[&_tbody_td]:[padding:10px] [@media(max-width:500px)]:[&_tbody_td]:[min-width:0] [@media(max-width:500px)]:[&_tbody_td]:[font-size:11px] [@media(max-width:500px)]:[&_tbody_td::before]:[content:attr(data-label)]',
  'sv-review-card':
    '[display:flex] [align-items:center] [gap:12px] [padding:15px] [border:1px_solid_#e0e7f1] [border-radius:10px] [&>div]:[flex:1] [&>div]:[min-width:0] [&_h4]:[margin:0_0_4px] [&_p]:[font-size:11px] [&_p]:[color:#6c8098] [&_p]:[overflow-wrap:anywhere]',
  'sv-modal-footer':
    '[display:flex] [justify-content:space-between] [align-items:center] [gap:12px] [border-top:1px_solid_#e3eaf4] [padding:15px_23px] [background:#fcfdff] [flex-shrink:0] [&>div]:[display:flex] [&>div]:[align-items:center] [&>div]:[gap:8px] [@media(min-width:721px)_and_(max-width:950px)]:[padding:13px_16px] [@media(max-width:720px)]:[flex-wrap:wrap] [@media(max-width:720px)]:[gap:8px] [@media(max-width:720px)]:[padding:10px] [@media(max-width:720px)]:[&>div]:[width:100%] [@media(max-width:720px)]:[&>div]:[justify-content:space-between] [@media(max-width:720px)]:[&>div]:[gap:5px] [@media(max-width:720px)]:[&_.sv-button]:[font-size:11px] [@media(max-width:720px)]:[&_.sv-button]:[padding:7px_10px] [@media(max-width:720px)]:[&_.sv-button]:[min-height:35px]',
  'sv-draft-status':
    '[font-size:10px] [color:#7b8ba3] [margin-right:8px] [@media(min-width:721px)_and_(max-width:950px)]:[display:none]',
  'sv-alert':
    '[padding:11px_14px] [border:1px_solid] [border-radius:8px] [font-size:12px] [line-height:1.6] [margin:0_0_14px] [overflow-wrap:anywhere] [&_ul]:[margin:4px_0] [&_ul]:[padding-left:19px]',
  'sv-alert-error':
    '[background:#fff2f1] [border-color:#f7c7c6] [color:#923d43]',
  'sv-alert-info':
    '[background:#edf7ff] [border-color:#c9e4fb] [color:#295c87]',
  'sv-alert-warning':
    '[background:#fffae7] [border-color:#f2e2a2] [color:#836323]',
  'sv-alert-success':
    '[background:#eaf9f1] [border-color:#c9ecdc] [color:#287557]',
  'sv-leave':
    '[position:absolute] [inset:0] [background:#19355488] [display:grid] [place-items:center] [padding:18px] [z-index:2] [&_section]:[background:white] [&_section]:[border-radius:13px] [&_section]:[box-shadow:0_10px_50px_#12334b33] [&_section]:[padding:24px] [&_section]:[width:min(530px,100%)] [&_section]:[max-height:90dvh] [&_section]:[overflow:auto] [&_h3]:[font-size:18px] [&_h3]:[color:#163958] [&_h3]:[margin:0_0_12px] [&_h3]:[font-weight:700] [&_p]:[font-size:13px] [&_p]:[line-height:1.7] [&_p]:[color:#687b93] [&_section>div]:[display:flex] [&_section>div]:[gap:8px] [&_section>div]:[justify-content:flex-end] [&_section>div]:[flex-wrap:wrap] [&_section>div]:[margin-top:20px] [@media(max-width:720px)]:[&_section]:[padding:18px]',
  'sv-small-overlay': '[z-index:10025]',
  'sv-preview':
    '[border:1px_solid_#dfebf3] [border-radius:12px] [background:linear-gradient(160deg,#eaf8fb,#f6f7fc)] [padding:17px] [position:sticky] [top:0] [min-width:0] [&_h3]:[font-size:14px] [&_h3]:[font-weight:700] [&_h3]:[color:#26445e] [&_h3]:[margin:0_0_13px] [@media(min-width:721px)_and_(max-width:950px)]:[padding:12px] [@media(max-width:720px)]:[position:static] [@media(max-width:720px)]:[max-width:100%] [@media(max-width:720px)]:[width:100%]',
  'sv-preview-tabs':
    '[display:flex] [gap:3px] [margin-bottom:13px] [&_button]:[background:transparent] [&_button]:[border:0] [&_button]:[border-radius:5px] [&_button]:[padding:5px_6px] [&_button]:[font-size:10px] [&_button]:[color:#6b7e8f] [&_button]:[flex:1] [&_button.selected]:[background:#c9f0e0] [&_button.selected]:[color:#167b55] [&_button.selected]:[font-weight:700]',
  'sv-preview-modes':
    '[display:flex] [gap:3px] [margin-bottom:13px] [&_button]:[background:transparent] [&_button]:[border:0] [&_button]:[border-radius:5px] [&_button]:[padding:5px_6px] [&_button]:[font-size:10px] [&_button]:[color:#6b7e8f] [&_button]:[flex:1] [background:#fff9] [border:1px_solid_#dbe6ed] [border-radius:7px] [padding:3px] [&_button.selected]:[background:#e2ecff] [&_button.selected]:[color:#3569b6] [&_button.selected]:[font-weight:600]',
  'sv-preview-phone':
    '[border-radius:12px] [border:1px_solid_#e3e7ee] [background:#f2eee6] [overflow:hidden] [box-shadow:0_3px_12px_#294d6a14] [@media(max-width:720px)]:[max-width:360px] [@media(max-width:720px)]:[margin:auto]',
  'sv-preview-brand':
    '[padding:13px_12px] [background:white] [display:flex] [align-items:center] [gap:9px] [border-bottom:1px_solid_#e5e9ed] [&_strong]:[font-size:12px] [&_strong]:[color:#25435e] [&_strong]:[display:block] [&_small]:[font-size:9px] [&_small]:[color:#8b9aa8]',
  'sv-preview-avatar':
    '[background:#164a7b] [color:white] [border-radius:50%] [width:32px] [height:32px] [display:grid] [place-items:center] [font-size:10px] [font-weight:700]',
  'sv-preview-content': '[padding:13px]',
  'sv-preview-message':
    '[padding:13px] [background:white] [border-radius:8px] [box-shadow:0_1px_3px_#435f7020] [font-size:11px] [color:#3e5064] [white-space:pre-wrap] [overflow-wrap:anywhere] [&_a]:[color:#1773bf] [&_a]:[word-break:break-all]',
  'sv-preview-question':
    '[background:white] [padding:12px] [border-radius:7px] [margin-bottom:8px] [min-width:0] [&_strong]:[display:block] [&_strong]:[font-size:11px] [&_strong]:[color:#344a61] [&_strong]:[margin-bottom:9px] [&_small]:[font-size:9px] [&_small]:[color:#7a8ba2] [&_p]:[font-size:11px] [&_p]:[line-height:1.6] [&_p]:[color:#344a61] [&_p]:[overflow-wrap:anywhere] [&_p]:[margin:0_0_7px]',
  'sv-preview-scale':
    '[display:grid] [grid-template-columns:repeat(6,minmax(0,1fr))] [gap:4px] [margin:8px_0] [&_span]:[display:grid] [&_span]:[place-items:center] [&_span]:[min-height:29px] [&_span]:[background:#f1f3f7] [&_span]:[border:1px_solid_#e2e6ed] [&_span]:[border-radius:5px] [&_span]:[font-size:11px] [&_span]:[color:#344c68] [&_span]:[font-weight:650] [@media(max-width:720px)]:[grid-template-columns:repeat(6,minmax(0,1fr))]',
  'sv-preview-stars': '[color:#dfa731] [font-size:23px] [letter-spacing:2px]',
  'sv-preview-choice':
    '[display:block] [padding:6px] [font-size:10px] [border:1px_solid_#e2e8ef] [border-radius:5px] [margin:4px_0] [color:#5b6c7f]',
  'sv-preview-text':
    '[border:1px_solid_#dce5ef] [border-radius:5px] [min-height:48px] [padding:8px] [font-size:10px] [color:#94a0b2]',
  'sv-preview-note':
    '[font-size:10px] [color:#677f95] [line-height:1.65] [margin:12px_0_0]',
  'sv-preview-submit':
    '[display:block] [text-align:center] [background:#1374d3] [color:#fff] [border-radius:6px] [padding:8px] [font-size:11px] [margin-top:10px]',
  'sv-preview-thank': '[font-size:10px] [color:#687b93] [padding:8px_0]',
  'sv-native-tabs':
    '[display:flex] [gap:8px] [flex-wrap:wrap] [margin:4px_0] [&_.sv-button[aria-selected=true]]:[background:#e7f2ff] [&_.sv-button[aria-selected=true]]:[border-color:#91b7f5] [&_.sv-button[aria-selected=true]]:[color:#0866ce]',
  'sv-backdrop':
    '[position:fixed] [inset:0] [z-index:10020] [background:#061e3d88] [backdrop-filter:blur(3px)] [display:flex] [align-items:center] [justify-content:center] [padding:22px] [@media(max-width:720px)]:[padding:8px]',
  'sv-close':
    '[background:none] [border:none] [font-size:27px] [color:#536780] [align-self:flex-start] [line-height:1] [padding:4px]',
  'sv-workspace':
    '[display:grid] [grid-template-columns:minmax(0,1fr)_300px] [gap:24px] [align-items:start] [@media(min-width:721px)_and_(max-width:950px)]:[grid-template-columns:minmax(0,1fr)_250px] [@media(min-width:721px)_and_(max-width:950px)]:[gap:16px] [@media(max-width:720px)]:[grid-template-columns:1fr]',
  'sv-main': '[border:0] [padding:0] [margin:0] [min-width:0]',
  'sv-section-heading':
    '[display:flex] [align-items:center] [gap:10px] [margin-bottom:17px] [&_h3]:[font-size:17px] [&_h3]:[color:#153759] [&_h3]:[font-weight:700] [&_h3]:[margin:0] [&_h3]:[outline:none] [&_p]:[font-size:11px] [&_p]:[color:#8190a7] [&_p]:[margin:3px_0_0]',
  'sv-kind':
    '[padding:15px_12px] [display:grid] [grid-template-columns:auto_1fr] [gap:8px] [border:1px_solid_#dee5ef] [border-radius:10px] [background:#fff] [text-align:left] [color:#536680] [&>span:first-child]:[font-size:20px] [&_strong]:[font-size:13px] [&_strong]:[color:#283e59] [&_small]:[display:block] [&_small]:[font-size:10px] [&_small]:[grid-column:1/-1] [&.purple]:[background:#faf6ff] [&.purple]:[color:#8547be] [&.amber]:[background:#fffbeb] [&.amber]:[color:#a77d14] [&.pink]:[background:#fff1f8] [&.pink]:[color:#c94b83] [&.selected]:[border:2px_solid_#8662db] [&.selected]:[box-shadow:0_0_0_2px_#eee6fb] [&.selected]:[padding:14px_11px] [@media(max-width:720px)]:[padding:11px_6px] [@media(max-width:720px)]:[gap:5px] [@media(max-width:720px)]:[&.selected]:[padding:10px_5px] [@media(max-width:720px)]:[&_small]:[font-size:9px]',
  'sv-count': '[text-align:right] [margin-top:-3px]',
  'sv-add-question':
    '[display:flex] [gap:9px] [justify-content:flex-end] [align-items:center] [&_select]:[max-width:175px] [@media(max-width:720px)]:[flex-wrap:wrap] [@media(max-width:720px)]:[justify-content:flex-start]',
  'sv-question-top':
    '[padding:13px] [display:flex] [gap:10px] [align-items:center]',
  'sv-question-select':
    '[background:transparent] [border:none] [flex:1] [text-align:left] [min-width:0] [&_strong]:[font-size:12px] [&_strong]:[display:block] [&_strong]:[margin:6px_0] [&_strong]:[overflow-wrap:anywhere] [&_strong]:[color:#334866] [&_small]:[font-size:10px] [&_small]:[color:#7b8ca4]',
  'sv-badge':
    '[font-size:10px] [display:inline-block] [border-radius:4px] [padding:2px_5px] [&.purple]:[background:#eee2ff] [&.purple]:[color:#7347a4] [&.blue]:[background:#e0f0ff] [&.blue]:[color:#2e70b7] [&.green]:[background:#ddf6ea] [&.green]:[color:#19866a] [&.amber]:[background:#fff0d9] [&.amber]:[color:#ac7b26]',
  'sv-option-row': '[display:grid] [grid-template-columns:1fr_auto] [gap:8px]',
  'sv-channel-foot':
    '[display:flex] [justify-content:space-between] [align-items:center] [padding:8px_15px] [background:#ffffff70] [color:#65837a] [font-size:10px]',
  'sv-preview-heading':
    '[display:flex] [align-items:center] [gap:7px] [font-size:14px] [font-weight:700] [margin-bottom:13px] [color:#22425e]',
  'sv-preview-live':
    '[margin-left:auto] [font-size:9px] [font-weight:600] [background:#d8f3e7] [color:#177b5e] [padding:2px_5px] [border-radius:4px]',
  'sv-preview-mode':
    '[display:flex] [gap:3px] [background:#fff9] [border:1px_solid_#dbe6ed] [border-radius:7px] [padding:3px] [margin-bottom:13px] [&_button]:[background:transparent] [&_button]:[border:none] [&_button]:[border-radius:5px] [&_button]:[padding:6px] [&_button]:[font-size:10px] [&_button]:[color:#6b7e8f] [&_button]:[flex:1] [&_.selected]:[background:#e2ecff] [&_.selected]:[color:#3569b6] [&_.selected]:[font-weight:600]',
  'sv-phone':
    '[border-radius:12px] [border:1px_solid_#e3e7ee] [background:#f2eee6] [overflow:hidden] [box-shadow:0_3px_12px_#294d6a14] [padding-bottom:10px]',
  'sv-phone-email': '[background:#eaf0fa]',
  'sv-phone-portal': '[background:#eeeafa]',
  'sv-phone-header':
    '[padding:13px_12px] [background:white] [display:flex] [align-items:center] [gap:9px] [border-bottom:1px_solid_#e5e9ed] [&_div]:[flex:1] [&_div]:[min-width:0] [&_strong]:[font-size:12px] [&_strong]:[color:#25435e] [&_strong]:[display:block] [&_small]:[font-size:9px] [&_small]:[color:#8b9aa8]',
  'sv-jrc-avatar':
    '[background:#164a7b] [color:white] [border-radius:50%] [width:32px] [height:32px] [display:grid] [place-items:center] [font-size:10px] [font-weight:700]',
  'sv-preview-paper':
    '[margin:12px_10px_3px] [background:white] [border-radius:8px] [padding:13px] [box-shadow:0_2px_4px_#334b6120] [min-width:0] [&_h4]:[font-size:14px] [&_h4]:[font-weight:700] [&_h4]:[color:#2f465e] [&_h4]:[margin:7px_0_12px] [&_h4]:[overflow-wrap:anywhere] [&_.sv-preview-question]:[padding:0] [&_.sv-preview-question]:[margin:12px_0] [&_.sv-preview-question]:[background:none]',
  'sv-preview-eyebrow':
    '[font-size:8px] [letter-spacing:.07em] [color:#6481a1] [font-weight:600]',
  'sv-preview-description':
    '[font-size:10px] [line-height:1.6] [color:#78889a] [margin-bottom:14px] [overflow-wrap:anywhere]',
  'sv-score-grid':
    '[display:grid] [grid-template-columns:repeat(6,minmax(0,1fr))] [gap:4px] [margin:8px_0] [&_span]:[display:grid] [&_span]:[place-items:center] [&_span]:[min-height:30px] [&_span]:[background:#f2f4f8] [&_span]:[border:1px_solid_#e2e6ed] [&_span]:[border-radius:5px] [&_span]:[font-size:11px] [&_span]:[color:#344c68] [&_span]:[font-weight:650] [&.stars_span]:[color:#c69120] [&.stars_span]:[font-size:17px] [&_small]:[grid-column:1/-1]',
  'sv-preview-options':
    '[display:grid] [gap:5px] [&_span]:[display:flex] [&_span]:[align-items:center] [&_span]:[gap:5px] [&_span]:[font-size:10px] [&_span]:[color:#5b6c7f] [&_i]:[display:inline-block] [&_i]:[border-radius:50%] [&_i]:[border:1px_solid_#c2cedb] [&_i]:[width:11px] [&_i]:[height:11px] [&_i]:[flex-shrink:0]',
  'sv-message-preview':
    '[white-space:pre-wrap] [overflow-wrap:anywhere] [font-size:12px] [color:#42546a] [margin:0] [line-height:1.7]',
  'sv-preview-link':
    '[color:#1179ce] [border-top:1px_solid_#edf1f6] [padding-top:8px] [margin-top:12px] [font-size:11px]',
  'sv-preview-safe':
    '[display:flex] [align-items:center] [gap:8px] [background:#ffffffaa] [border:1px_solid_#e0eaf0] [border-radius:8px] [padding:11px] [margin-top:13px] [font-size:12px] [color:#3d6b88] [&_strong]:[display:block] [&_strong]:[font-size:10px] [&_strong]:[color:#416b86] [&_small]:[font-size:9px] [&_small]:[color:#7a90a2] [&_small]:[display:block] [&_small]:[margin-top:4px]',
  'sv-preview-tab':
    '[&.blue.selected]:[background:#d8eaff] [&.blue.selected]:[color:#246bb2] [&.purple.selected]:[background:#e8dbff] [&.purple.selected]:[color:#7650b1]',
};

export function surveyClasses(value) {
  const names = normalizeClass(value).split(/\s+/).filter(Boolean);
  return [names.join(' '), ...names.map(name => styles[name] || '')].join(' ');
}
