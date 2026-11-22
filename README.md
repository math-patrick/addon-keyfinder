# Keyfinder

Localizador de grupos Mythic+ para quem joga key alta. WoW retail Midnight (12.1.x).

## Instalação

1. Extraia a pasta `Keyfinder` em `World of Warcraft/_retail_/Interface/AddOns/`.
2. Abra o jogo e confira se o addon está ligado na lista de AddOns.
3. Para abrir: `/kf`, a aba lateral ou o botão **Keyfinder** no Localizador de Grupos (I), o ícone no compartimento de addons do minimapa, ou um atalho em *Opções › Atalhos › AddOns*.

## O que faz

**Abrir pelo Localizador**
- Com o Localizador de Grupos (I) aberto, aparece uma aba lateral com o ícone do Keyfinder à direita da janela e um botão **Keyfinder** na barra de título.
- A aba lateral brilha e mostra um contador quando a última busca tem grupos com nota 75+ (inclusive buscas feitas na janela da Blizzard).

**Buscar**
- Topo: seu rating e sua key à esquerda, faixa de dungeons à direita. O retrato da janela é a sua spec.
- Embaixo da lista, como no Localizador: **Filtros** e **Ordenar** à esquerda, **Buscar** à direita.
- Faixa de dungeons centralizada, com o seu best timado em cada uma. Clique filtra, botão direito deixa só aquela, **Todas** limpa. Bolinha laranja = suas 3 dungeons mais fracas.
- Lista enxuta: nota, título do grupo (onde está a key) e dungeon, **best do líder** nessa dungeon, rating do **Líder** e **Vagas**.
- Detalhe: arte da dungeon, **Aceite**, **seu best** nessa dungeon e **Timar**, composição, líder (com o ícone do Parse Academy) e os 4 motivos mais relevantes da nota.
- **Filtros** (menu nativo): prioridade da nota, faixa de key estimada (inclusive "Perto do meu nível"), rating e best do líder, idade, estilo e filtros de vaga/rating/utilidade.
- Rodapé: suas candidaturas como ícones das dungeons; clique leva ao grupo.

**Como a nota é calculada (usa as suas runs)**
- Lê o seu resumo de M+ da temporada (best por dungeon, timado ou não, pontos) e calibra a curva de pontos com as suas runs timadas.
- **Nível da key**: aparece no título do grupo. O Keyfinder nunca mostra palpite de nível; uma estimativa interna só ajuda a ordenar a nota.
- **Upgrades**: mostra só keys entre o seu nível base e a faixa acima dele. No nível base, só as dungeons em que a key é upgrade pra você; acima, todas. Nível base (automático = seu menor best timado +1) e faixa ficam em *Opções › AddOns › Keyfinder* ou no menu Filtros. O nível usado no filtro é estimado internamente e nunca aparece na tela.
- **Aceite**: seu best timado aqui x key, seu rating x o do líder, Bloodlust/battle res que você leva, amigos, auto-aceite, exigências.
- **Timar**: experiência do líder nesta dungeon, a sua, e se o rating dele combina com a key.

**Progresso**
- Um card por dungeon, da mais fraca para a mais forte: best, pontos, próximo passo e quanto rating ele dá. **Procurar grupos** já filtra e busca.

**Meu grupo** (quem monta o grupo)
- **Anúncio preenchido**: ao criar um grupo no Localizador da Blizzard, o Keyfinder preenche item level e rating mínimos a partir da sua key (e privado/cross-faction). O que você digitar fica. Dá pra desligar em *Opções › AddOns › Keyfinder*.
- Banner da dungeon anunciada, sua key e a composição atual com os ícones de Bloodlust e battle res.
- **Recomendações**: o que falta (roles, Bloodlust, battle res e quais classes trazem), que best procurar pra sua key e aviso quando não há rating mínimo.
- **Candidatos**: quantos estão esperando por role, rating médio e quantos já timaram a sua key.
- Lista ordenada por encaixe, com "recomendado" no melhor candidato de cada vaga, rating, best na dungeon, ilvl comparado ao seu, botões Convidar/Recusar e o ícone do **Parse Academy** (usa o addon Parse Academy se estiver instalado; senão mostra o link pra copiar).

**Watchlist**
- Regras do tipo "The Blinding Vale, líder 3000+, best +16, vaga para minha role".
- A cada busca, o addon confere as regras e avisa, mesmo com a janela fechada. Os avisos possíveis são som, ícone piscando na barra de tarefas, aviso no centro da tela e uma janela com botão **Candidatar**.
- **Usar F8** coloca a busca no F8. Com isso, procurar um grupo vira apertar F8 de vez em quando.

## Limitações do jogo (respeitadas de propósito)

- **Nível da key:** o título do grupo, onde fica o "+16", é protegido. Nenhum addon consegue lê-lo ou filtrá-lo, mas o Keyfinder **mostra** o título. Para filtrar por nível, use o filtro "best do líder nesta dungeon" ou digite o nível na busca da Blizzard; o Keyfinder lê esses resultados.
- **Busca:** só acontece com clique ou tecla (hardware event). O addon nunca busca sozinho em segundo plano. A Watchlist funciona em cima das buscas que você dispara.
- **Candidatar, convidar e recusar:** também exigem clique. Por isso não existe "auto-apply".
- **Secret values (Midnight):** qualquer valor que o jogo marque como secreto é ignorado (tratado como desconhecido), sem erro.
- **Criar o anúncio:** continua no Localizador da Blizzard, porque o campo de título só aceita texto digitado pelo jogador.
- O addon não modifica frames nem dados da Blizzard (para não causar taint). Ele só adiciona um botão no Localizador e usa os templates nativos: `ButtonFrameTemplate`, `InsetFrameTemplate`, `UIPanelButtonTemplate`, `PanelTabButtonTemplate`, `UICheckButtonTemplate`, `MinimalSliderWithSteppersTemplate`, `WowStyle1DropdownTemplate`, `WowScrollBoxList` + `MinimalScrollBar`, `GameTooltip` e `StaticPopup`.

## Comandos

- `/kf` abre e fecha a janela
- `/kf buscar` faz uma busca
- `/kf reset` volta a janela para o centro

## Primeiro teste no jogo (checklist)

1. `/kf` abre a janela com as abas Buscar, Progresso e Watchlist.
2. A faixa de dungeons mostra as 8 dungeons da temporada com o seu best em cada uma.
3. **Buscar** preenche a lista, e o cabeçalho mostra quantos grupos sobraram após os filtros.
4. Clicar num grupo preenche o painel da direita, com título, composição e motivos.
5. Candidatar e cancelar funcionam.
6. Criar uma regra e buscar de novo dispara o aviso (ou use **Testar alerta**).

Se aparecer erro Lua, mande o texto completo do erro (de preferência pelo BugSack/BugGrabber).
