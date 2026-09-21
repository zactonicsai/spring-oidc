# How it works — explained with a grocery store and a school

## 1. What is a language model?

Imagine a game: I say "peanut butter and ..." and you shout "jelly!". A language model is a computer
program that plays that game over and over. It looks at the words so far and guesses the next word
(actually the next *token* — a word or piece of a word). Then it adds that guess and guesses again.
String enough guesses together and you get a sentence, a shell script, or a poem.

**TinyLlama-1.1B-Chat** is one of these. The "1.1B" means it has about **1.1 billion parameters** —
tiny numbers (dials) that control which guess it makes. The "Chat" part means it was already taught
to take turns like a conversation.

**Grocery store version:** the model is a new employee who has read every cookbook, catalog and
manual in the world. Ask anything and they will say *something* — but they have never worked *your* register.

## 2. Tokens = items on the conveyor belt

The model cannot read letters. Text is chopped into tokens, like groceries placed one at a time on
the checkout belt. "ip addr show" might be 4 tokens; a long script might be 60. That is why we set a
**context length** (512 in this project): the belt has a maximum length, and our scripts are short.

## 3. What is fine-tuning?

You don't send the employee back to school for four years. You give them a **training shift**:
"When a customer asks for X, do Y." Show them enough real examples and the behaviour becomes a habit.

Fine-tuning is exactly that: we show the model **question → answer** pairs and nudge its dials so
those answers become more likely. The base model already knows English and a lot about Linux;
we only teach the *job*: answer with a bash script, nothing else, and say "I don't know" when unsure.

## 4. The flashcards (training data)

Each line in `data/train_small.jsonl` is one flashcard:

```
FRONT (instruction):  Show the routing table
BACK  (output):       #!/bin/bash
                      ip route show
```

**School version:** studying for a vocabulary test. You don't memorise the whole dictionary; you
make 80 flashcards for the words on Friday's quiz.

Why does every answer start with `#!/bin/bash`? Because patterns are what the model learns best.
If every card's answer starts the same way, the model's very first guess after your question will
be `#!/bin/bash` — and once it is "in script mode" it stays there.

## 5. The rulebook (system prompt)

The employee wears a name tag that says **"Network aisle. Commands only."** That is the system
prompt in `system_prompt.txt`. It is glued to the front of every flashcard during training and to
every question later. The model learns the *combination* (rulebook + question → answer), which is
why you must use the same rulebook when you test it.

## 6. "I don't know" — the most important flashcards

A cashier who is asked "where is the pharmacy in the *other* store across town?" should say
"I don't know", not invent an aisle number. Language models love to invent aisle numbers — the
technical name is **hallucination**.

So about **1 in 5** flashcards has the answer

```
#!/bin/bash
echo "I don't know"
```

for questions that are off-topic (bake bread), for other systems (Windows, Cisco, macOS), for things
that need a web page or a password, or that are too vague ("fix my network"). The model learns the
**edges** of its job. Too few of these and it never says it; too many and it refuses real questions.
The build script prints the percentage so you can keep it around 15–25%.

## 7. LoRA — the cheat sheet clipped to the apron

Changing all 1.1 billion dials needs a lot of memory and time. **LoRA (Low-Rank Adaptation)** freezes
the whole brain and adds a small **cheat sheet** — a few million extra dials on the side. Only the
cheat sheet is trained.

- The cheat sheet file is about **50 MB** instead of 2.2 GB.
- Training is much faster and needs far less memory.
- You can keep several cheat sheets for one employee (networking today, printing tomorrow).
- The **rank** (16 here) is how big the cheat sheet is. 8–32 is normal for a small job.

`scripts/chat_test.py` **merges** the cheat sheet into the brain when it loads, so answering is fast.
`scripts/export_merge.py` saves that merged version to disk for sharing.

## 8. What happens during training (epochs, loss, learning rate, batches)

Picture studying for the quiz:

- **Epoch** — one trip through the whole flashcard deck. We make 3 trips.
- **Batch size** — how many cards you look at before you adjust your habits. 2 cards, and we add
  up 4 such batches before adjusting (**gradient accumulation**) = 8 cards per adjustment.
- **Loss** — your score on the practice quiz, where *lower is better*. Before training, TinyLlama's
  loss on our cards is around 2 (it is guessing wildly). Good training brings it under 0.5. If it
  hits 0.05 on the first trip, you are just memorising the cards (see overfitting).
- **Learning rate** — how strongly you correct yourself after each mistake. Erase one letter
  (tiny rate: slow) or rip the page out (huge rate: you lose what you knew). 0.0002 (2e-4) is the
  usual sweet spot for LoRA.
- **Warm-up** — the first few steps use a tiny learning rate so the model does not panic before
  it has seen what the cards look like.
- **Gradient** — the direction to turn each dial to make the loss smaller. Computing it is the
  expensive part, which is why training is slower than answering.

## 9. Grading only the answer

When the teacher marks your quiz, she grades your *answers*, not whether you copied the question
correctly. Our training does the same: the question and rulebook tokens are marked "don't grade"
(label `-100`), only the script tokens count. In the Desktop app this is the **Train on Completions**
switch. It makes small datasets learn much faster.

## 10. Overfitting — memorising vs understanding

Two students study for the same quiz. One memorises the exact 80 cards; the other understands the
words. On Friday the teacher rephrases the questions. The memoriser fails.

That is **overfitting**: loss near zero on the practice cards, bad answers to slightly different
questions. Fixes: more cards, cards that say the same thing in different words, fewer epochs, or a
smaller rank. Always test with `data/eval_questions.txt`, which are *not* in the deck.

## 11. Why a CPU works (and why a GPU is faster)

- A **CPU** is one brilliant cashier: can do anything, one job at a time, very fast per job.
- A **GPU** is 500 baggers who each do the same simple move at the same time.

Training a model is mostly baggers' work (millions of tiny multiplications that can all happen at
once). So a GPU finishes hours sooner. But with a *small* model and a *small* deck, the single
cashier gets it done in 10–40 minutes, which is fine for learning and for real small jobs.

Apple Silicon Macs have a built-in GPU that PyTorch can use ("MPS"); the scripts use it
automatically. The Unsloth Desktop app uses Apple's MLX library for the same reason.

## 12. Quantization (4-bit, GGUF) — rounding the prices

A 1.1B model in full precision stores each dial as a 32-bit number (2.2 GB in 16-bit, 4.4 GB in 32-bit).
**Quantizing** rounds each dial to a smaller number — like writing prices as $3 instead of $2.99 so
the whole list fits on a sticky note. 8-bit (Q8_0) is almost lossless; 4-bit (Q4_K_M) is a quarter
the size with a small quality cost. **GGUF** is the file format that stores a quantized model in
one file that Ollama and llama.cpp can open on any laptop.

Note: the popular "QLoRA / load in 4-bit" trick in GPU tutorials uses a library (bitsandbytes) that
needs an NVIDIA GPU. On a CPU we train in full precision and quantize *after* training instead.

## 13. Temperature — following the recipe

When the model picks the next token it has a list of candidates with probabilities. **Temperature**
controls how adventurous it is. High temperature = a chef improvising; low = following the recipe
to the gram. Shell commands must be exact, so we use temperature 0 (greedy: always the top choice).

## 14. Why keep the deck small at first?

A small deck trains in minutes, so you find mistakes fast: a wrong command, a bad JSON line, too
many refusals. Fix, retrain, repeat. When the behaviour is right, add decks in `data/extra/` and
retrain. It is a science-fair project: change one thing, measure, then change the next.
