/** @file       range-find.c
 *              UNIX-spirit utility to find ranges in sorted files. The first
 *              field of every line must be a number or a date.
 *  @author     Wes Garland, wes@kingsds.network
 *  @date       Apr 2020
 */

#ifdef SUPPORT_GETDATE
# define _GNU_SOURCE
#endif
#define _XOPEN_SOURCE 500
#include <time.h>
#include <string.h>
#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <errno.h>
#include <string.h>

#ifndef MAX_LINE_SIZE
# define MAX_LINE_SIZE 65536
#endif

typedef long long atoll_t(const char *nptr);

static atoll_t *atoll_fn;
static char buf[MAX_LINE_SIZE];
static int seconds = 0;

void searchBackwardsToLineStart(FILE *file)
{
  int ch;
  off_t cur = ftell(file) - 1;
  int i;  
  do
  {
    fseek(file, --cur, SEEK_SET);
    ch = fgetc(file);
    if (ch == '\n')
      break;
  } while(!ferror(file));
}

off_t findClosestLineStart(FILE *file, long long target)
{
  long long minVal, maxVal, curVal;
  off_t minPos, maxPos, curPos, curPosEOL, lastCurPos, lastCurPosEOL;
  int maxTries=1000;
  
  /* Find lowest number */
  rewind(file);
  fgets(buf, sizeof(buf), file);
  curVal=minVal=atoll_fn(buf);
  minPos=0;
  
  /* Find highest number */
  fseek(file, 0, SEEK_END);
  searchBackwardsToLineStart(file);
  curPos = maxPos = ftell(file);
  fgets(buf, sizeof(buf), file);
  maxVal = atoll_fn(buf);
  curPosEOL = curPos + strlen(buf);

#ifdef DEBUG  
  printf("%9.9s > %9.9s %9.9s %9.9s", "target", "minVal", "curVal", "maxVal");
  printf("\t| %7s %7s/%7s %7s\n", "minPos", "curPos", "lastEOL", "maxPos");
#endif
  
  do
  {
    lastCurPos = curPos;
    lastCurPosEOL = curPosEOL;
    
    fseek(file, minPos + (maxPos - minPos)/2, SEEK_SET);
    searchBackwardsToLineStart(file);
    curPos=ftell(file);
    fgets(buf, sizeof(buf), file);
    curPosEOL = curPos + strlen(buf);
    curVal=atoll_fn(buf);

    if (curVal == target)
      break;
    
    if (curVal > target)
    { 
      /* target between curVal and maxVal */
#ifdef DEBUG
      printf("%09lld > %09lld %09lld %09lld", target % 10000000000, minVal % 10000000000, curVal % 10000000000, maxVal % 10000000000);
      printf("\t| %7ld %7ld/%7ld %7ld\n", minPos, curPos, lastCurPosEOL, maxPos);
#endif
      maxVal = curVal;
      maxPos = curPos;
    }
    else
    {
      /* target between curVal and minVal */
#ifdef DEBUG
      printf("%09lld < %09lld %09lld %09lld", target % 10000000000, minVal % 10000000000, curVal % 10000000000, maxVal % 10000000000);
      printf("\t| %7ld %7ld/%7ld %7ld\n", minPos, curPos, lastCurPosEOL, maxPos);
#endif
      minVal = curVal;
      minPos = curPos;
    }
    if (!--maxTries)
    {
      fprintf(stderr, "Search bug! Giving up.\n");
      break;
    }
  } while(minPos != maxPos && curPos != lastCurPos);// && curPos != lastCurPosEOL);

  if (curVal > target)
    return minPos;

  if (curVal < target)
    return maxPos;
  
  return curPos;
}

static time_t timeBuf;
static char *timeFormat = "%b %e %T";

long long logdateParse(const char *buf)
{
  struct tm *tm_p;
  time_t et;

  if (!timeBuf)
    time(&timeBuf);
  tm_p = localtime(&timeBuf);
  
  if (!strptime(buf, timeFormat, tm_p))
  {
    fprintf(stderr, "Could not parse date '%s'. Stop.\n", buf);
    exit(4);
  }

  et = mktime(tm_p);

  return seconds ? et : 1000 * et;
}

#ifdef SUPPORT_GETDATE
long long getdateParse(const char *buf)
{
  struct tm *tm_p;
  static const char *errors[] =
  {
    "no error",
    "The DATEMSK environment variable is not defined, or its value is an empty string.",
    "The template file specified by DATEMSK cannot be opened for reading.",
    "Failed to get file status information.",
    "The template file is not a regular file.",
    "An error was encountered while reading the template file.",
    "Memory allocation failed (not enough memory available).",
    "There is no line in the file that matches the input.",
    "Invalid input specification."
  };

  if (getuid() == 0 || geteuid() == 0)
  {
    fprintf(stderr, "getdate parsing not available when running as root - DATEMSK can make us open anything\n");
    exit(3);
  }

  tm_p = getdate(buf);
  if (!tm_p)
  {
    const char *errstr;
    extern int getdate_err;

    if (getdate_err < 0 || getdate_err > (sizeof errors / sizeof errors[0]))
      errstr = "invalid error";
    else
      errstr = errors[getdate_err];
    fprintf(stderr, "Could not parse date '%s' (%s). Stop.\n", buf, errstr);
    exit(2);
  }
  
  return 1000 * mktime(tm_p);
}
#endif

void usage(const char *argvZero)
{
  printf(
      "range-find - find ranges of lines in files sorted by first column\n"
      "Copyright (c) 2020 Kings Distributed Systems. All Rights Reserved.\n"
      "\n"
      "Usage - %s <-f filename> <-l #> <-u #> [-h] [-s|-d|-p <fmt>]\n"
      "Where:\n"
      " -h shows this help.\n"
      " -s selects syslog-style date parsing in place of numbers from now on\n"
#ifdef SUPPORT_GETDATE
      " -g parses dates with getdate() in place of numbers from now on (non root)\n"
#endif
      " -p parses dates with the given strptime(3) format from now on\n"
      " -n parses numbers from now on (default)\n"
      " -l specifies the lower bounds of the range\n"
      " -u specifies the upper bounds of the range\n"
      " -f specifies the name of the file to search\n"
      " -S toggles internal time representation between ms and s (default=%s)\n"
      "\n"
      "Note: Files with lines longer than %li bytes may result in failed searches.\n",
      argvZero, (seconds ? "s" : "ms"), sizeof(buf)
  );
  exit(0);
}

int main(int argc, char * const *argv)
{
  char *s;
  long long rangeStart = 0, rangeEnd = 0;
  off_t rangeStartPos, rangeEndPos, pos;
  FILE *file;
  int ch;
  const char *filename = NULL;
  
  atoll_fn = &atoll;

  while ((ch = getopt(argc, argv,
#ifdef SUPPORT_GETDATE
                      "g"
#endif
                      "Shsp:f:l:u:n")) != EOF)
  {
    switch(ch)
    {
      case 'S':
        seconds = seconds ? 0 : 1;
        break;      
      case 'h':
        usage(argv[0]);
        break;
      case 'l':
        rangeStart = atoll_fn(optarg);
        break;
      case 'u':
        rangeEnd = atoll_fn(optarg);
        break;
      case 'n':
        atoll_fn = &atoll;
        break;
      case 'p':
        timeFormat = strdup(optarg);
      case 's':
        atoll_fn = &logdateParse;
        break;
#ifdef SUPPORT_GETDATE
      case 'g':
        atoll_fn = &getdateParse;
        break;
#endif
      case 'f':
        filename = strdup(optarg);
        break;
    }
  }
  
  if (!filename)
    usage(argv[0]);
  
  file = fopen(filename, "r");
  if (!file) {
    fprintf(stderr, "Error opening '%s' (%s)\n", filename, strerror(errno));
    return 1;
  }

  if (getenv("DEBUG_RANGE_FIND"))
    fprintf(stderr, "Range: %lld - %lld\n", rangeStart, rangeEnd);

  if (rangeEnd < rangeStart)
  {
    fprintf(stderr, "Error: range must end after start\n");
    return 2;
  }

  rangeStartPos = findClosestLineStart(file, rangeStart);
  rangeEndPos = findClosestLineStart(file, rangeEnd); 

  fseek(file, rangeStartPos, SEEK_SET);
  pos = rangeStartPos;
  while(pos < rangeEndPos)
  {
    if (!fgets(buf, sizeof(buf), file))
      return 1;
    fwrite(buf, 1, strlen(buf), stdout);
    pos += strlen(buf);
  }
  return 0;
}

