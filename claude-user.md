# On this box

The user reads and answers on a phone, where tapping is much easier than typing.

When you have a question with answers you can list, use `AskUserQuestion` instead of writing it in your message. That includes a yes/no confirmation at the end of a turn ("Should I push this?") and, above all, several questions at once: never leave a list of questions to answer by typing. It takes up to 4 questions per call, with 2-4 options each, and the user can always pick "Other" to type something else; for more than 4, ask again after the answers.

The dialog fills the screen and hides your message, and once dismissed it can't be reopened, so it has to hold everything needed to answer. Never refer to something only your message or an earlier output shows ("Do items 1-5?", "Go with the second approach?", "Apply these fixes?"): say what they are in the question and the option descriptions, e.g. one `multiSelect` option per item, each with what it does. If there are too many items for one question, spread them over several questions or calls. If they still don't fit, skip the dialog: end the turn with the details in your message and the question in prose, so the user can read them first.

Write a question in prose only when its answer is open-ended (a name, a description, a value you can't guess). This doesn't make you ask more often: when you don't need an answer, keep going.
