// The Claims page's script (content/docs/evidence/index.md names it as `module:`): the replay and
// the state field. The anatomy figure keeps its numbered notes here; its leaders (annotate.js)
// need the homepage's wide margins.
import { mountReplay, mountField } from "/claims/figures.js";

mountReplay(document.querySelector(".replay"));
mountField(document.querySelector(".field"));
