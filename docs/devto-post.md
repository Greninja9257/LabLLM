---
title: "I built a native macOS app for training small language models"
published: true
tags: ai, webdev, programming, opensource
cover_image: https://raw.githubusercontent.com/Greninja9257/LabLLM/master/docs/media/captures/labllm-hero.gif
---

I have been building **LabLLM**, a free native macOS app for training small Transformer/LLM models from scratch using your own datasets.

The idea is simple: training a language model should not require duct-taping together scripts, notebooks, dashboards, random folders of checkpoints, and a terminal window you are afraid to close.

LabLLM gives you a GUI for the whole loop:

- build a GPT-style model with random initialization
- import text or instruction data
- train locally with Apple Silicon + MLX
- watch training and validation loss
- save checkpoints
- fine-tune behavior
- sample during training
- chat with the model you trained

Repo: https://github.com/Greninja9257/LabLLM  
Releases: https://github.com/Greninja9257/LabLLM/releases  
Discussions: https://github.com/Greninja9257/LabLLM/discussions

![LabLLM animated welcome background](https://raw.githubusercontent.com/Greninja9257/LabLLM/master/docs/media/captures/labllm-hero.gif)

## Why I made it

Most LLM tooling is built for people who are already comfortable living in scripts and infrastructure.

That is powerful, but it also makes the first step weirdly expensive. If you are curious about language models and want to answer a question like:

> What happens if I train a tiny model on this dataset?

you should be able to try it without first building half a research platform.

LabLLM is meant to feel more like a workshop:

- bring a dataset
- choose or build a model
- start training
- watch what happens
- inspect the result
- try the next idea

It is not trying to replace serious production ML infrastructure. It is for learning, experiments, local model development, fine-tuning, and making the training process visible.

## What it can do right now

LabLLM is already able to:

- create GPT-style decoder models
- train from scratch
- fine-tune on instruction/conversation data
- run LoRA fine-tuning
- run DPO preference training
- browse and import datasets
- mix datasets by row count or percentage
- show live training metrics
- show validation loss as a separate curve
- generate live samples during training
- save and load checkpoints
- export model cards
- chat with local models
- serve a local OpenAI-shaped HTTP endpoint
- export quantized models

![LabLLM dataset browser](https://raw.githubusercontent.com/Greninja9257/LabLLM/master/docs/media/captures/labllm-data.png)

![LabLLM training dashboard](https://raw.githubusercontent.com/Greninja9257/LabLLM/master/docs/media/captures/labllm-training.png)

![LabLLM model manager](https://raw.githubusercontent.com/Greninja9257/LabLLM/master/docs/media/captures/labllm-models.png)

## Recent focus: making training more trustworthy

The current priority is not adding flashy features.

The priority is making the training system scientifically trustworthy:

- deterministic dataset sampling
- fixed validation sets
- correct dataset windowing
- masked padding loss
- safer DPO truncation
- checkpoint metadata
- real optimizer-state resume for new checkpoints
- tests around core ML behavior

That work matters because a training app should not merely look good. If a loss curve moves, the user should be able to trust what it means.

## Why contributors would be genuinely helpful

This project has a lot of good contribution paths that do not require being an ML researcher.

Useful areas right now:

- SwiftUI polish
- dataset import edge cases
- tokenizer robustness
- MLX training correctness tests
- LoRA and DPO invariants
- docs and tutorials
- small starter recipes
- accessibility
- crash reports and reproduction cases
- better onboarding for people new to training models

If you are into Swift, ML tooling, local-first software, or making machine learning easier to understand, this is a good project to jump into.

## The kind of app I want this to become

I want LabLLM to be the app you open when you want to learn how language models work by actually training one.

Not just reading about loss curves. Watching one.

Not just seeing a Transformer diagram. Building a small Transformer and testing it.

Not just downloading a model. Training something small enough to understand and personal enough to care about.

## It is beta software

LabLLM is still early. It can train and fine-tune real models, but it is not a polished final release.

Expect rough edges, bugs, and fast-moving changes. If you try it, please keep backups of important projects and report anything confusing or broken.

That feedback is exactly what helps the project improve.

## Try it, star it, break it, improve it

If this sounds interesting:

- try the latest beta
- star the repo so more people find it
- open an issue if something breaks
- join Discussions if you have ideas
- send a focused pull request if you want to help build it

GitHub: https://github.com/Greninja9257/LabLLM  
Latest releases: https://github.com/Greninja9257/LabLLM/releases  
Contributing guide: https://github.com/Greninja9257/LabLLM/blob/master/CONTRIBUTING.md  
Discussions: https://github.com/Greninja9257/LabLLM/discussions

I would especially love contributors who care about making ML tools feel understandable, trustworthy, and fun to explore.
