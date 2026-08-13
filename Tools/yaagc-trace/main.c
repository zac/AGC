/*
 * Dump a compact JSONL golden trace from yaAGC for comparison with the Swift engine.
 *
 * Usage: yaagc-trace <rom.bin> [max_cycles] [--keys cycle:octal,...]
 *
 * Sampling matches Sources/AGC/AGCGoldenTrace.swift:
 *   every cycle through 200, every 1000 through 100000, every 10000 thereafter,
 *   plus every injected key cycle.
 *
 * --keys injects channel-15 DSKY keycodes when CycleCounter equals `cycle`
 * (after the increment at the start of agc_engine), matching Swift
 * sendDSKYKey + runEngine.
 */

#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "agc_engine.h"

#define TRACE_DENSE_UNTIL 200ULL
#define TRACE_MID_UNTIL 100000ULL
#define TRACE_MID_STRIDE 1000ULL
#define TRACE_FAR_STRIDE 10000ULL
#define TRACE_FAR_UNTIL 1000000ULL
#define TRACE_MAX_KEYS 32

typedef struct
{
  uint64_t cycle;
  int channel;
  int value;
} TraceKey;

extern TraceKey TraceKeys[TRACE_MAX_KEYS];
extern int TraceKeyCount;
extern int TraceKeyIndex;

static int
is_key_cycle (uint64_t cycle)
{
  int i;
  for (i = 0; i < TraceKeyCount; i++)
    {
      if (TraceKeys[i].cycle == cycle)
	return 1;
    }
  return 0;
}

static int
should_sample (uint64_t cycle)
{
  if (cycle <= TRACE_DENSE_UNTIL)
    return 1;
  if (cycle <= TRACE_MID_UNTIL && (cycle % TRACE_MID_STRIDE) == 0)
    return 1;
  if ((cycle % TRACE_FAR_STRIDE) == 0)
    return 1;
  if (is_key_cycle (cycle))
    return 1;
  return 0;
}

static unsigned
u16 (int16_t word)
{
  return ((unsigned) (uint16_t) word) & 0177777;
}

static unsigned
u15 (int16_t word)
{
  return ((unsigned) (uint16_t) word) & 077777;
}

static void
dump_sample (const agc_t *State)
{
  const int16_t *e0 = State->Erasable[0];
  printf ("{\"c\":%" PRIu64
	  ",\"a\":%u,\"l\":%u,\"q\":%u,\"z\":%u,\"eb\":%u,\"fb\":%u,\"bb\":%u,"
	  "\"t1\":%u,\"t3\":%u,\"ch7\":%u,\"ch11\":%u,\"ch13\":%u,\"ch32\":%u,\"ch77\":%u,"
	  "\"s1\":%u,\"s2\":%u,\"ec\":%u,\"isr\":%u,\"ie\":%u,\"pf\":%u,"
	  "\"ir\":[%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d]}\n",
	  State->CycleCounter, u16 (e0[RegA]), u16 (e0[RegL]), u16 (e0[RegQ]),
	  u16 (e0[RegZ]), u16 (e0[RegEB]), u16 (e0[RegFB]), u16 (e0[RegBB]),
	  u15 (e0[RegTIME1]), u15 (e0[RegTIME3]),
	  u15 (State->OutputChannel7), u15 (State->InputChannel[011]),
	  u15 (State->InputChannel[013]), u15 (State->InputChannel[032]),
	  u15 (State->InputChannel[077]), u15 (State->InputChannel[ChanSCALER1]),
	  u15 (State->InputChannel[ChanSCALER2]), (unsigned) State->ExtraCode,
	  (unsigned) State->InIsr, (unsigned) State->AllowInterrupt,
	  (unsigned) State->PendFlag, (int) State->InterruptRequests[0],
	  (int) State->InterruptRequests[1], (int) State->InterruptRequests[2],
	  (int) State->InterruptRequests[3], (int) State->InterruptRequests[4],
	  (int) State->InterruptRequests[5], (int) State->InterruptRequests[6],
	  (int) State->InterruptRequests[7], (int) State->InterruptRequests[8],
	  (int) State->InterruptRequests[9],
	  (int) State->InterruptRequests[10]);
}

static int
parse_keys (char *spec)
{
  char *token;
  char *save = NULL;

  for (token = strtok_r (spec, ",", &save); token != NULL;
       token = strtok_r (NULL, ",", &save))
    {
      char *colon;
      unsigned long long cycle;
      unsigned int value;

      if (TraceKeyCount >= TRACE_MAX_KEYS)
	{
	  fprintf (stderr, "too many keys (max %d)\n", TRACE_MAX_KEYS);
	  return -1;
	}
      colon = strchr (token, ':');
      if (colon == NULL)
	{
	  fprintf (stderr, "bad key spec '%s' (expected cycle:octal)\n", token);
	  return -1;
	}
      *colon = '\0';
      cycle = strtoull (token, NULL, 10);
      value = (unsigned int) strtoul (colon + 1, NULL, 8);
      if (cycle == 0)
	{
	  fprintf (stderr, "key cycle must be > 0\n");
	  return -1;
	}
      TraceKeys[TraceKeyCount].cycle = cycle;
      TraceKeys[TraceKeyCount].channel = 015;
      TraceKeys[TraceKeyCount].value = (int) (value & 077777);
      TraceKeyCount++;
    }
  return 0;
}

int
main (int argc, char **argv)
{
  agc_t State;
  uint64_t max_cycles = TRACE_FAR_UNTIL;
  uint64_t cycle;
  int rc;
  int argi;

  if (argc < 2)
    {
      fprintf (stderr, "usage: %s <rom.bin> [max_cycles] [--keys cycle:octal,...]\n",
	       argv[0]);
      return 2;
    }

  for (argi = 2; argi < argc; argi++)
    {
      if (strcmp (argv[argi], "--keys") == 0)
	{
	  if (argi + 1 >= argc)
	    {
	      fprintf (stderr, "--keys requires cycle:octal,...\n");
	      return 2;
	    }
	  if (parse_keys (argv[++argi]) != 0)
	    return 2;
	}
      else
	{
	  max_cycles = strtoull (argv[argi], NULL, 10);
	  if (max_cycles == 0)
	    {
	      fprintf (stderr, "max_cycles must be > 0\n");
	      return 2;
	    }
	}
    }

  memset (&State, 0, sizeof (State));
  rc = agc_engine_init (&State, argv[1], NULL, 1);
  if (rc != 0)
    {
      fprintf (stderr, "agc_engine_init failed: %d\n", rc);
      return 1;
    }

  dump_sample (&State);
  for (cycle = 1; cycle <= max_cycles; cycle++)
    {
      agc_engine (&State);
      if (should_sample (State.CycleCounter))
	dump_sample (&State);
    }
  return 0;
}
