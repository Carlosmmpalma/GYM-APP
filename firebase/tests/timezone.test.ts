// Última ronda — a hora das aulas andava uma hora no verão.
//
// Não precisa de emulador: é aritmética de calendário, e é exatamente
// o tipo de coisa que se parte sem ninguém dar por isso até chegar a
// última semana de março.

import { describe, expect, it } from 'vitest';

import {
  addWeeksPreservingWallClock,
  utcToZonedWallClock,
  zonedWallClockToUtc,
} from '../functions/src/lib/timeZone';

const LISBOA = 'Europe/Lisbon';

/** "2026-04-01T18:00:00.000Z" — mais legível do que um número. */
function iso(date: Date): string {
  return date.toISOString();
}

describe('Hora do relógio → instante', () => {
  it('no inverno, Lisboa é UTC', () => {
    // 25 de março de 2026: ainda antes da mudança (último domingo do
    // mês é 29).
    const instant = zonedWallClockToUtc({
      year: 2026,
      month: 3,
      day: 25,
      hour: 19,
      minute: 0,
      timeZone: LISBOA,
    });
    expect(iso(instant)).toBe('2026-03-25T19:00:00.000Z');
  });

  it('no verão, a aula das 19:00 são 18:00 UTC', () => {
    // O bug: `setUTCHours(19)` guardava 19:00Z, que em Lisboa são
    // 20:00 — e a aula aparecia uma hora depois na app.
    const instant = zonedWallClockToUtc({
      year: 2026,
      month: 4,
      day: 1,
      hour: 19,
      minute: 0,
      timeZone: LISBOA,
    });
    expect(iso(instant)).toBe('2026-04-01T18:00:00.000Z');
  });

  it('acerta no próprio dia em que o relógio muda', () => {
    // 29 de março de 2026, o dia da mudança: às 19:00 já é verão.
    const instant = zonedWallClockToUtc({
      year: 2026,
      month: 3,
      day: 29,
      hour: 19,
      minute: 0,
      timeZone: LISBOA,
    });
    expect(iso(instant)).toBe('2026-03-29T18:00:00.000Z');
  });

  it('e no dia em que o relógio recua', () => {
    // 25 de outubro de 2026: às 19:00 já é inverno outra vez.
    const instant = zonedWallClockToUtc({
      year: 2026,
      month: 10,
      day: 25,
      hour: 19,
      minute: 0,
      timeZone: LISBOA,
    });
    expect(iso(instant)).toBe('2026-10-25T19:00:00.000Z');
  });

  it('serve qualquer fuso, não só o de Lisboa', () => {
    const instant = zonedWallClockToUtc({
      year: 2026,
      month: 7,
      day: 1,
      hour: 9,
      minute: 30,
      timeZone: 'America/New_York',
    });
    expect(iso(instant)).toBe('2026-07-01T13:30:00.000Z');
  });
});

describe('Instante → hora do relógio', () => {
  it('lê a hora local a partir do instante', () => {
    const local = utcToZonedWallClock(
      new Date('2026-07-15T18:00:00.000Z'),
      LISBOA,
    );
    expect(local).toEqual({
      year: 2026,
      month: 7,
      day: 15,
      hour: 19,
      minute: 0,
    });
  });
});

describe('Semana a semana', () => {
  it('a aula continua às 19:00 depois da mudança da hora', () => {
    // 25 de março às 19:00 (inverno) + 1 semana = 1 de abril às 19:00
    // (verão). Somar 7×24h daria 20:00.
    const semanaSeguinte = addWeeksPreservingWallClock(
      new Date('2026-03-25T19:00:00.000Z'),
      1,
      LISBOA,
    );
    expect(iso(semanaSeguinte)).toBe('2026-04-01T18:00:00.000Z');
    expect(utcToZonedWallClock(semanaSeguinte, LISBOA).hour).toBe(19);
  });

  it('e continua às 19:00 quando o relógio recua', () => {
    const semanaSeguinte = addWeeksPreservingWallClock(
      new Date('2026-10-21T18:00:00.000Z'),
      1,
      LISBOA,
    );
    expect(utcToZonedWallClock(semanaSeguinte, LISBOA).hour).toBe(19);
    expect(iso(semanaSeguinte)).toBe('2026-10-28T19:00:00.000Z');
  });

  it('fora das semanas de mudança é uma soma normal', () => {
    const semanaSeguinte = addWeeksPreservingWallClock(
      new Date('2026-07-01T18:00:00.000Z'),
      1,
      LISBOA,
    );
    expect(iso(semanaSeguinte)).toBe('2026-07-08T18:00:00.000Z');
  });
});
