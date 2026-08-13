/*
 * Minimal I/O so the yaAGC engine can be linked without sockets or the debugger.
 * Channel 7 (superbank) is latched here, matching SocketAPI.c — NullAPI leaves it
 * unset, which diverges from the Swift engine and from a real yaAGC DSKY session.
 *
 * Optional DSKY key injection is driven by TraceKeys[] from main.c.
 */

#include "agc_engine.h"

#include <stdint.h>

#define TRACE_MAX_KEYS 32

typedef struct
{
  uint64_t cycle;
  int channel;
  int value;
} TraceKey;

TraceKey TraceKeys[TRACE_MAX_KEYS];
int TraceKeyCount = 0;
int TraceKeyIndex = 0;

void
UnblockSocket (int SocketNum)
{
  (void) SocketNum;
}

void
BacktraceAdd (agc_t *State, int Cause)
{
  (void) State;
  (void) Cause;
}

void
ChannelOutput (agc_t *State, int Channel, int Value)
{
  if (Channel == 7)
    {
      State->InputChannel[7] = State->OutputChannel7 = (Value & 0160);
      return;
    }
  if (Channel == 013 && 0600 == (0600 & Value) && !CmOrLm)
    {
      State->Erasable[0][042] = LastRhcPitch;
      State->Erasable[0][043] = LastRhcYaw;
      State->Erasable[0][044] = LastRhcRoll;
    }
}

int
ChannelInput (agc_t *State)
{
  if (TraceKeyIndex < TraceKeyCount
      && State->CycleCounter == TraceKeys[TraceKeyIndex].cycle)
    {
      int channel = TraceKeys[TraceKeyIndex].channel;
      int value = TraceKeys[TraceKeyIndex].value;
      TraceKeyIndex++;
      WriteIO (State, channel, value);
      if (channel == 015)
	State->InterruptRequests[5] = 1;
    }
  return 0;
}

void
ChannelRoutine (agc_t *State)
{
  (void) State;
}

void
ShiftToDeda (agc_t *State, int Data)
{
  (void) State;
  (void) Data;
}

void
RequestRadarData (agc_t *State)
{
  (void) State;
}

int Portnum = 19697;
Swrite_t *SwritePtr = 0;
