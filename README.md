# Godot Game — Caballero pisos

Plataformas 2D hecho con **Godot 4.6**.

## Cómo abrirlo

Abre la carpeta del proyecto desde el gestor de proyectos de Godot 4.6. La
carpeta `.godot/` no está en el repositorio: Godot la regenera sola la primera
vez que abras el proyecto (puede tardar un poco en reimportar las texturas).

## Controles

| Acción | Tecla |
|---|---|
| Moverse | A / D o flechas |
| Arriba / abajo (agarre en pared) | W / S o flechas |
| Saltar (doble salto) | Espacio |
| Atacar | K |
| Rodar (esquiva con invulnerabilidad) | J |
| Agacharse | C |
| Inventario | I |

## Contenido

- **Jugador** (`player/`): correr, doble salto, ataque, rodar, giro rápido y
  agarre a paredes con salto de pared. Barra de vida propia e inventario con
  ranuras de talismanes, arma y armadura.
- **Enemigos** (`Enemies/`): medusa y sátiro, con rango de visión, persecución
  y ataque cuerpo a cuerpo.
- **Jefes** (`Bosses/`):
  - *Chairman* — sala de oficina, con seis ataques (bola de fuego, carámbano,
    corte de trueno, chorro de agua, estrella fugaz y espada invocada).
  - *Minotauro* — arena de selva, con hachazo y embestida periódica.
  - *Dragón* — en construcción.
- **Niveles** (`levels/`): nivel principal que alterna tramos de bosque y de
  caverna, con puntos de guardado (estatuas de ángel) y portales entre zonas.

## Créditos

Los sprites y tilesets son packs de terceros usados en el proyecto; los
derechos pertenecen a sus autores.
