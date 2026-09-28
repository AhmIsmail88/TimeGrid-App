/// Wraps [text] in a "left-to-right isolate" (U+2066 … U+2069).
///
/// Dates like "21 Sep" are a left-to-right run sitting inside an Arabic
/// paragraph. Without isolation the bidi algorithm re-orders the pieces and
/// the day and the month swap places on screen, so "21 Sep – 20 Oct" came out
/// looking like "Sep 21 – Oct 20". An isolate pins the run's own direction
/// without changing anything else on the line.
String ltrRun(String text) => '\u2066$text\u2069';
