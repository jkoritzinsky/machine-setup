import { createCanvas, joinSession } from "@github/copilot-sdk/extension";
import { createNotificationCanvas } from "./canvas.mjs";

let session;
const implementation = createNotificationCanvas({
    triggerCleanup: async () => {
        if (!session) {
            throw new Error("The extension session is not ready.");
        }

        await session.send({
            prompt: [
                "Run the notification-cleanup skill now at the user's request.",
                "Follow the skill's safety rules exactly: report stale-closed candidates and skipped notifications,",
                "and ask for confirmation before DELETE calls unless the user has explicitly authorized proceeding without confirmation.",
            ].join(" "),
        });
    },
});

session = await joinSession({
    canvases: [
        createCanvas({
            id: "github-notification-triage",
            displayName: "GitHub notifications",
            description: "Interactive GitHub notification triage and pull request review dashboard.",
            inputSchema: {
                type: "object",
                properties: {
                    filter: {
                        type: "string",
                        enum: ["all", "my-prs", "other-open-prs", "other-draft-prs", "stacked-prs", "reviews", "assigned", "high"],
                    },
                },
                additionalProperties: false,
            },
            actions: implementation.actions,
            open: implementation.open,
            onClose: implementation.onClose,
        }),
    ],
});
