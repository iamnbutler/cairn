// Every link preview card bongo builds, drawn by satori: the layouts and content/og/cards.txt.hbs
// pass label, title and line. The card itself is tools/og/card.ts, which the Worker draws too.
import { type Args, cardHtml } from "../../../../tools/og/card.ts";

export default ({ label, title, line }: Args) => cardHtml({ label, title, line });
