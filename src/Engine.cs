// Reclaim engine: fast, junction-safe file walking, measuring, deleting, scanning
// and duplicate detection. Compiled at run time by Add-Type (C# 5, .NET Framework 4.x
// and .NET 6+ compatible) and cached as a DLL in %LOCALAPPDATA%\Reclaim\engine.
//
// Rules this file follows everywhere:
//  * never follows junctions or symbolic links (a link is removed, its target never touched)
//  * uses \\?\ paths internally, so paths longer than 260 characters work
//  * a file or folder that cannot be read or deleted is counted and skipped, never fatal
//  * every long operation can run on a background thread (Job) and be cancelled
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Threading;
using Microsoft.Win32.SafeHandles;

namespace Reclaim
{
    public class WalkStats
    {
        public long Bytes;          // bytes found (measure) or bytes that would be / were freed (delete)
        public long Files;
        public long Dirs;
        public long Links;          // junctions / symlinks seen (never followed)
        public long Errors;         // access denied, unreadable folders
        public long InUse;          // files locked by a running program
        public long DeletedFiles;
        public long DeletedDirs;
        public string LastError;
        public void Add(WalkStats o)
        {
            Bytes += o.Bytes; Files += o.Files; Dirs += o.Dirs; Links += o.Links; Errors += o.Errors;
            InUse += o.InUse; DeletedFiles += o.DeletedFiles; DeletedDirs += o.DeletedDirs;
            if (o.LastError != null) LastError = o.LastError;
        }
    }

    public class FileEntry
    {
        public string Path; public long Bytes; public DateTime LastWrite;
        public FileEntry(string path, long bytes, DateTime lastWrite) { Path = path; Bytes = bytes; LastWrite = lastWrite; }
    }

    public class ScanResult
    {
        public string Root;
        public Dictionary<string, long> DirBytes = new Dictionary<string, long>(StringComparer.OrdinalIgnoreCase);
        public Dictionary<string, long> ExtBytes = new Dictionary<string, long>(StringComparer.OrdinalIgnoreCase);
        public Dictionary<string, long> ExtFiles = new Dictionary<string, long>(StringComparer.OrdinalIgnoreCase);
        public List<FileEntry> TopFiles = new List<FileEntry>();
        public long OldBytes;       // bytes in files not modified for OldDays
        public int OldDays;
        public WalkStats Stats = new WalkStats();
    }

    public class DupGroup
    {
        public string Hash; public long Bytes; public List<FileEntry> Files = new List<FileEntry>();
        public long Wasted { get { return Bytes * (Files.Count - 1); } }
    }

    public class Job
    {
        public volatile bool Done;
        public volatile bool Cancel;
        public long Progress;               // items processed (Interlocked)
        public long ProgressBytes;
        public volatile string Phase = "";
        public volatile string Current = "";
        public object Result;
        public Exception Error;
        private Thread thread;

        internal static Job Start(Func<Job, object> body)
        {
            Job j = new Job();
            j.thread = new Thread(delegate ()
            {
                try { j.Result = body(j); }
                catch (Exception e) { j.Error = e; }
                finally { j.Done = true; }
            });
            j.thread.IsBackground = true;
            j.thread.Start();
            return j;
        }
        public bool Wait(int milliseconds) { return thread.Join(milliseconds); }
        internal void Tick(long n, long bytes) { Interlocked.Add(ref Progress, n); if (bytes != 0) Interlocked.Add(ref ProgressBytes, bytes); }
    }

    public static class Engine
    {
        // ---------------------------------------------------------------- paths and safety
        public static string ToLong(string p)
        {
            if (p.StartsWith(@"\\?\")) return p;
            if (p.StartsWith(@"\\")) return @"\\?\UNC\" + p.Substring(2);
            return @"\\?\" + p;
        }
        public static string ToShort(string p)
        {
            if (p.StartsWith(@"\\?\UNC\")) return @"\\" + p.Substring(8);
            if (p.StartsWith(@"\\?\")) return p.Substring(4);
            return p;
        }
        static bool IsLink(FileSystemInfo i) { return (i.Attributes & FileAttributes.ReparsePoint) != 0; }
        static bool IsDir(FileSystemInfo i) { return (i.Attributes & FileAttributes.Directory) != 0; }

        /// Depth of a path: C:\ = 1, C:\a = 2, C:\a\b = 3.
        public static int Depth(string path)
        {
            string p = ToShort(path).TrimEnd('\\');
            return p.Split(new char[] { '\\' }, StringSplitOptions.RemoveEmptyEntries).Length;
        }

        /// Last line of defence (the PowerShell layer has a fuller protected-path list).
        public static void Guard(string path, int minDepth)
        {
            if (string.IsNullOrWhiteSpace(path)) throw new ArgumentException("Empty path");
            string s = ToShort(path);
            if (s.IndexOf('*') >= 0 || s.IndexOf('?') >= 0) throw new ArgumentException("Wildcards are not allowed here: " + s);
            if (!Path.IsPathRooted(s) || s.Length < 3 || s[1] != ':') throw new ArgumentException("Only full local paths (X:\\...) are allowed: " + s);
            if (minDepth < 2) minDepth = 2;
            if (Depth(s) < minDepth) throw new InvalidOperationException("Refusing to touch a top-level path: " + s);
        }

        static DateTime Cutoff(int olderThanDays)
        {
            return olderThanDays > 0 ? DateTime.UtcNow.AddDays(-olderThanDays) : DateTime.MaxValue;
        }

        static List<FileSystemInfo> List(string dir, WalkStats s)
        {
            try { return new List<FileSystemInfo>(new DirectoryInfo(dir).EnumerateFileSystemInfos()); }
            catch (Exception e) { s.Errors++; s.LastError = e.Message; return null; }
        }

        // ---------------------------------------------------------------- measure
        public static WalkStats Measure(string root, int olderThanDays, Job job)
        {
            WalkStats s = new WalkStats();
            DateTime cut = Cutoff(olderThanDays);
            string lr = ToLong(root);
            if (File.Exists(lr))
            {
                FileInfo f = new FileInfo(lr);
                if (f.LastWriteTimeUtc < cut) { s.Files = 1; s.Bytes = f.Length; }
                return s;
            }
            if (!Directory.Exists(lr)) return s;
            Stack<string> stack = new Stack<string>();
            stack.Push(lr);
            while (stack.Count > 0)
            {
                if (job != null && job.Cancel) break;
                string d = stack.Pop();
                if (job != null) job.Current = ToShort(d);
                List<FileSystemInfo> items = List(d, s);
                if (items == null) continue;
                long n = 0, b = 0;
                foreach (FileSystemInfo it in items)
                {
                    if (IsDir(it))
                    {
                        if (IsLink(it)) { s.Links++; continue; }
                        s.Dirs++; stack.Push(it.FullName);
                    }
                    else
                    {
                        FileInfo f = (FileInfo)it;
                        if (IsLink(f)) { s.Links++; continue; }
                        if (f.LastWriteTimeUtc < cut) { s.Files++; s.Bytes += f.Length; b += f.Length; }
                        n++;
                    }
                }
                if (job != null) job.Tick(n, b);
            }
            return s;
        }

        public static Job StartMeasure(string[] roots, int olderThanDays)
        {
            return Job.Start(delegate (Job j)
            {
                WalkStats total = new WalkStats();
                foreach (string r in roots) { if (j.Cancel) break; j.Phase = r; total.Add(Measure(r, olderThanDays, j)); }
                return total;
            });
        }

        // ---------------------------------------------------------------- delete
        /// contentsOnly: empty the folder but keep it. olderThanDays: only files older than that.
        /// dryRun: count what would be deleted, touch nothing.
        public static WalkStats Delete(string root, bool contentsOnly, int olderThanDays, bool dryRun, int minDepth, Job job)
        {
            Guard(root, minDepth);
            WalkStats s = new WalkStats();
            DateTime cut = Cutoff(olderThanDays);
            string lr = ToLong(root);
            if (File.Exists(lr))
            {
                FileInfo f = new FileInfo(lr);
                if (f.LastWriteTimeUtc < cut) DeleteFile(f, dryRun, s, job);
                return s;
            }
            DirectoryInfo di = new DirectoryInfo(lr);
            if (!di.Exists) return s;
            if (IsLink(di))
            {
                // the target itself is a link: remove the link only
                if (!contentsOnly && cut == DateTime.MaxValue) RemoveLink(di.FullName, dryRun, s);
                return s;
            }
            DeleteTree(lr, cut, dryRun, s, job, !contentsOnly);
            return s;
        }

        static void DeleteFile(FileInfo f, bool dryRun, WalkStats s, Job job)
        {
            long len = IsLink(f) ? 0 : f.Length;
            if (dryRun) { s.Bytes += len; s.Files++; s.DeletedFiles++; if (job != null) job.Tick(1, len); return; }
            try
            {
                if ((f.Attributes & (FileAttributes.ReadOnly | FileAttributes.System | FileAttributes.Hidden)) != 0) f.Attributes = FileAttributes.Normal;
                f.Delete();
                s.Bytes += len; s.Files++; s.DeletedFiles++;
                if (job != null) job.Tick(1, len);
            }
            catch (IOException e) { s.InUse++; s.LastError = e.Message; }
            catch (UnauthorizedAccessException e) { s.Errors++; s.LastError = e.Message; }
        }

        static void RemoveLink(string path, bool dryRun, WalkStats s)
        {
            s.Links++;
            if (dryRun) return;
            try { Directory.Delete(path, false); }
            catch (Exception e) { s.Errors++; s.LastError = e.Message; }
        }

        static bool DeleteTree(string dir, DateTime cut, bool dryRun, WalkStats s, Job job, bool removeSelf)
        {
            if (job != null) { if (job.Cancel) return false; job.Current = ToShort(dir); }
            List<FileSystemInfo> items = List(dir, s);
            if (items == null) return false;
            bool empty = true;
            foreach (FileSystemInfo it in items)
            {
                if (job != null && job.Cancel) return false;
                if (IsDir(it))
                {
                    if (IsLink(it))
                    {
                        // junction or directory symlink: never followed. Removed only in a full clean.
                        if (cut == DateTime.MaxValue) RemoveLink(it.FullName, dryRun, s); else empty = false;
                        continue;
                    }
                    if (!DeleteTree(it.FullName, cut, dryRun, s, job, true)) empty = false;
                }
                else
                {
                    FileInfo f = (FileInfo)it;
                    if (f.LastWriteTimeUtc >= cut) { empty = false; continue; }
                    long before = s.DeletedFiles;
                    DeleteFile(f, dryRun, s, job);
                    if (s.DeletedFiles == before) empty = false;
                }
            }
            if (removeSelf && empty)
            {
                if (dryRun) { s.DeletedDirs++; return true; }
                try
                {
                    DirectoryInfo di = new DirectoryInfo(dir);
                    if ((di.Attributes & FileAttributes.ReadOnly) != 0) di.Attributes = FileAttributes.Directory;
                    di.Delete(false);
                    s.DeletedDirs++;
                    return true;
                }
                catch (Exception e) { s.Errors++; s.LastError = e.Message; return false; }
            }
            return empty;
        }

        public static Job StartDelete(string[] roots, bool contentsOnly, int olderThanDays, bool dryRun, int minDepth)
        {
            // guard every root before anything is deleted
            foreach (string r in roots) Guard(r, minDepth);
            return Job.Start(delegate (Job j)
            {
                WalkStats total = new WalkStats();
                foreach (string r in roots) { if (j.Cancel) break; j.Phase = r; total.Add(Delete(r, contentsOnly, olderThanDays, dryRun, minDepth, j)); }
                return total;
            });
        }

        // ---------------------------------------------------------------- scan (space hogs)
        public static ScanResult Scan(string root, int maxDepth, int topCount, long minFileBytes, int oldDays, Job job)
        {
            ScanResult r = new ScanResult();
            r.Root = root; r.OldDays = oldDays;
            DateTime old = oldDays > 0 ? DateTime.UtcNow.AddDays(-oldDays) : DateTime.MinValue;
            string lr = ToLong(root.TrimEnd('\\') + "\\");
            long topMin = 0;
            // each stack entry carries the folders (up to maxDepth below root) its files count towards
            Stack<KeyValuePair<string, string[]>> stack = new Stack<KeyValuePair<string, string[]>>();
            stack.Push(new KeyValuePair<string, string[]>(lr, new string[0]));
            while (stack.Count > 0)
            {
                if (job != null && job.Cancel) break;
                KeyValuePair<string, string[]> e = stack.Pop();
                if (job != null) job.Current = ToShort(e.Key);
                List<FileSystemInfo> items = List(e.Key, r.Stats);
                if (items == null) continue;
                long n = 0, b = 0;
                foreach (FileSystemInfo it in items)
                {
                    if (IsDir(it))
                    {
                        if (IsLink(it)) { r.Stats.Links++; continue; }
                        r.Stats.Dirs++;
                        string[] buckets = e.Value;
                        if (buckets.Length < maxDepth)
                        {
                            string sp = ToShort(it.FullName);
                            string[] nb = new string[buckets.Length + 1];
                            Array.Copy(buckets, nb, buckets.Length);
                            nb[buckets.Length] = sp;
                            buckets = nb;
                            if (!r.DirBytes.ContainsKey(sp)) r.DirBytes[sp] = 0;
                        }
                        stack.Push(new KeyValuePair<string, string[]>(it.FullName, buckets));
                    }
                    else
                    {
                        FileInfo f = (FileInfo)it;
                        if (IsLink(f)) { r.Stats.Links++; continue; }
                        long len = f.Length;
                        r.Stats.Files++; r.Stats.Bytes += len; n++; b += len;
                        foreach (string k in e.Value) r.DirBytes[k] += len;
                        string ext = f.Extension.ToLowerInvariant();
                        if (ext.Length == 0 || ext.Length > 12) ext = "(none)";
                        long v;
                        r.ExtBytes[ext] = (r.ExtBytes.TryGetValue(ext, out v) ? v : 0) + len;
                        r.ExtFiles[ext] = (r.ExtFiles.TryGetValue(ext, out v) ? v : 0) + 1;
                        DateTime lw = f.LastWriteTimeUtc;
                        if (lw < old) r.OldBytes += len;
                        if (len >= minFileBytes && (r.TopFiles.Count < topCount || len > topMin))
                        {
                            r.TopFiles.Add(new FileEntry(ToShort(f.FullName), len, lw.ToLocalTime()));
                            if (r.TopFiles.Count > topCount)
                            {
                                r.TopFiles.Sort(delegate (FileEntry x, FileEntry y) { return y.Bytes.CompareTo(x.Bytes); });
                                r.TopFiles.RemoveAt(r.TopFiles.Count - 1);
                            }
                            topMin = r.TopFiles.Count < topCount ? 0 : MinBytes(r.TopFiles);
                        }
                    }
                }
                if (job != null) job.Tick(n, b);
            }
            r.TopFiles.Sort(delegate (FileEntry x, FileEntry y) { return y.Bytes.CompareTo(x.Bytes); });
            return r;
        }
        static long MinBytes(List<FileEntry> l) { long m = long.MaxValue; foreach (FileEntry f in l) if (f.Bytes < m) m = f.Bytes; return m; }

        public static Job StartScan(string root, int maxDepth, int topCount, long minFileBytes, int oldDays)
        {
            return Job.Start(delegate (Job j) { j.Phase = root; return Scan(root, maxDepth, topCount, minFileBytes, oldDays, j); });
        }

        // ---------------------------------------------------------------- find folders by name
        /// Returns folders whose name is in `names` (not descending into them), skipping links,
        /// .git and any folder named in `skip`.
        public static List<string> FindDirs(string[] roots, string[] names, string[] skip, Job job)
        {
            HashSet<string> want = new HashSet<string>(names, StringComparer.OrdinalIgnoreCase);
            HashSet<string> no = new HashSet<string>(skip, StringComparer.OrdinalIgnoreCase);
            List<string> found = new List<string>();
            WalkStats s = new WalkStats();
            foreach (string root in roots)
            {
                Stack<string> stack = new Stack<string>();
                stack.Push(ToLong(root.TrimEnd('\\') + "\\"));
                while (stack.Count > 0)
                {
                    if (job != null && job.Cancel) return found;
                    string d = stack.Pop();
                    if (job != null) { job.Current = ToShort(d); job.Tick(1, 0); }
                    List<FileSystemInfo> items = List(d, s);
                    if (items == null) continue;
                    foreach (FileSystemInfo it in items)
                    {
                        if (!IsDir(it) || IsLink(it)) continue;
                        if (want.Contains(it.Name)) { found.Add(ToShort(it.FullName)); continue; }
                        if (no.Contains(it.Name)) continue;
                        stack.Push(it.FullName);
                    }
                }
            }
            return found;
        }

        public static Job StartFindDirs(string[] roots, string[] names, string[] skip)
        {
            return Job.Start(delegate (Job j) { j.Phase = "Looking for build folders"; return FindDirs(roots, names, skip, j); });
        }

        // ---------------------------------------------------------------- project activity
        /// Newest last-write time of any file up to maxDepth below dir, skipping folders in skipNames
        /// (build folders, .git). Used to tell whether a project is still being worked on.
        public static DateTime NewestWrite(string dir, int maxDepth, string[] skipNames, int maxItems)
        {
            HashSet<string> no = new HashSet<string>(skipNames, StringComparer.OrdinalIgnoreCase);
            DateTime newest = DateTime.MinValue;
            WalkStats s = new WalkStats();
            Stack<KeyValuePair<string, int>> stack = new Stack<KeyValuePair<string, int>>();
            stack.Push(new KeyValuePair<string, int>(ToLong(dir), 0));
            int seen = 0;
            while (stack.Count > 0 && seen < maxItems)
            {
                KeyValuePair<string, int> e = stack.Pop();
                List<FileSystemInfo> items = List(e.Key, s);
                if (items == null) continue;
                foreach (FileSystemInfo it in items)
                {
                    seen++;
                    if (IsLink(it)) continue;
                    if (IsDir(it))
                    {
                        if (no.Contains(it.Name)) continue;
                        if (e.Value + 1 < maxDepth) stack.Push(new KeyValuePair<string, int>(it.FullName, e.Value + 1));
                    }
                    else if (it.LastWriteTime > newest) newest = it.LastWriteTime;
                }
            }
            return newest;
        }

        // ---------------------------------------------------------------- size on disk
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        static extern uint GetCompressedFileSizeW(string lpFileName, out uint lpFileSizeHigh);

        /// Real space a file takes on disk (sparse, compressed and virtual disk files are smaller than Length).
        public static long SizeOnDisk(string path)
        {
            uint high;
            uint low = GetCompressedFileSizeW(ToLong(path), out high);
            if (low == 0xFFFFFFFF && Marshal.GetLastWin32Error() != 0)
            {
                try { return new FileInfo(ToLong(path)).Length; } catch { return -1; }
            }
            return ((long)high << 32) + low;
        }

        // ---------------------------------------------------------------- duplicates
        [StructLayout(LayoutKind.Sequential)]
        struct BY_HANDLE_FILE_INFORMATION
        {
            public uint FileAttributes;
            public System.Runtime.InteropServices.ComTypes.FILETIME CreationTime, LastAccessTime, LastWriteTime;
            public uint VolumeSerialNumber, FileSizeHigh, FileSizeLow, NumberOfLinks, FileIndexHigh, FileIndexLow;
        }
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool GetFileInformationByHandle(SafeFileHandle h, out BY_HANDLE_FILE_INFORMATION info);

        static FileStream OpenRead(string longPath)
        {
            return new FileStream(longPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete, 1 << 20, FileOptions.SequentialScan);
        }

        /// volume + file index identifies hard links (same data, several names): not real duplicates.
        static string FileId(string longPath)
        {
            try
            {
                using (FileStream fs = OpenRead(longPath))
                {
                    BY_HANDLE_FILE_INFORMATION i;
                    if (GetFileInformationByHandle(fs.SafeFileHandle, out i))
                        return i.VolumeSerialNumber.ToString("X") + ":" + i.FileIndexHigh.ToString("X") + ":" + i.FileIndexLow.ToString("X");
                }
            }
            catch { }
            return null;
        }

        static string PartialHash(string longPath, long len)
        {
            const int chunk = 64 * 1024;
            using (FileStream fs = OpenRead(longPath))
            using (SHA1 sha = SHA1.Create())
            {
                byte[] buf = new byte[chunk];
                int r = fs.Read(buf, 0, chunk);
                sha.TransformBlock(buf, 0, r, null, 0);
                if (len > 2 * chunk)
                {
                    fs.Seek(-chunk, SeekOrigin.End);
                    r = fs.Read(buf, 0, chunk);
                    sha.TransformBlock(buf, 0, r, null, 0);
                }
                sha.TransformFinalBlock(new byte[0], 0, 0);
                return BitConverter.ToString(sha.Hash).Replace("-", "");
            }
        }

        static string FullHash(string longPath, Job job)
        {
            using (FileStream fs = OpenRead(longPath))
            using (SHA256 sha = SHA256.Create())
            {
                byte[] buf = new byte[1 << 20];
                int r;
                while ((r = fs.Read(buf, 0, buf.Length)) > 0)
                {
                    if (job != null && job.Cancel) throw new OperationCanceledException();
                    sha.TransformBlock(buf, 0, r, null, 0);
                    if (job != null) job.Tick(0, r);
                }
                sha.TransformFinalBlock(new byte[0], 0, 0);
                return BitConverter.ToString(sha.Hash).Replace("-", "");
            }
        }

        public static List<DupGroup> FindDuplicates(string[] roots, long minBytes, string[] skipDirs, Job job)
        {
            HashSet<string> no = new HashSet<string>(skipDirs, StringComparer.OrdinalIgnoreCase);
            Dictionary<long, List<FileEntry>> bySize = new Dictionary<long, List<FileEntry>>();
            WalkStats s = new WalkStats();
            HashSet<string> seenRoots = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            if (job != null) job.Phase = "1/3 Listing files";
            foreach (string root in roots)
            {
                string lr = ToLong(root.TrimEnd('\\') + "\\");
                if (!seenRoots.Add(lr)) continue;
                Stack<string> stack = new Stack<string>();
                stack.Push(lr);
                while (stack.Count > 0)
                {
                    if (job != null && job.Cancel) return new List<DupGroup>();
                    string d = stack.Pop();
                    if (job != null) job.Current = ToShort(d);
                    List<FileSystemInfo> items = List(d, s);
                    if (items == null) continue;
                    foreach (FileSystemInfo it in items)
                    {
                        if (IsLink(it)) continue;
                        if (IsDir(it)) { if (!no.Contains(it.Name)) stack.Push(it.FullName); continue; }
                        FileInfo f = (FileInfo)it;
                        if (f.Length < minBytes) continue;
                        List<FileEntry> l;
                        if (!bySize.TryGetValue(f.Length, out l)) { l = new List<FileEntry>(); bySize[f.Length] = l; }
                        l.Add(new FileEntry(f.FullName, f.Length, f.LastWriteTime));
                        if (job != null) job.Tick(1, 0);
                    }
                }
            }

            // drop hard links of the same file, then compare a quick hash of the first and last 64 KB
            if (job != null) { job.Phase = "2/3 Quick compare"; job.Progress = 0; }
            List<List<FileEntry>> candidates = new List<List<FileEntry>>();
            foreach (KeyValuePair<long, List<FileEntry>> kv in bySize)
            {
                if (kv.Value.Count < 2) continue;
                if (job != null && job.Cancel) return new List<DupGroup>();
                Dictionary<string, FileEntry> unique = new Dictionary<string, FileEntry>();
                List<FileEntry> distinct = new List<FileEntry>();
                foreach (FileEntry f in kv.Value)
                {
                    string id = FileId(f.Path);
                    if (id != null) { if (unique.ContainsKey(id)) continue; unique[id] = f; }
                    distinct.Add(f);
                }
                if (distinct.Count < 2) continue;
                Dictionary<string, List<FileEntry>> byPartial = new Dictionary<string, List<FileEntry>>();
                foreach (FileEntry f in distinct)
                {
                    string h;
                    try { h = PartialHash(f.Path, kv.Key); } catch { continue; }
                    List<FileEntry> l;
                    if (!byPartial.TryGetValue(h, out l)) { l = new List<FileEntry>(); byPartial[h] = l; }
                    l.Add(f);
                    if (job != null) job.Tick(1, 0);
                }
                foreach (List<FileEntry> l in byPartial.Values) if (l.Count > 1) candidates.Add(l);
            }

            // full SHA-256 only for files that still match
            if (job != null) { job.Phase = "3/3 Full compare (SHA-256)"; job.Progress = 0; job.ProgressBytes = 0; }
            List<DupGroup> groups = new List<DupGroup>();
            foreach (List<FileEntry> l in candidates)
            {
                Dictionary<string, DupGroup> byFull = new Dictionary<string, DupGroup>();
                foreach (FileEntry f in l)
                {
                    if (job != null) { if (job.Cancel) return groups; job.Current = ToShort(f.Path); }
                    string h;
                    try { h = FullHash(f.Path, job); }
                    catch (OperationCanceledException) { return groups; }
                    catch { continue; }
                    DupGroup g;
                    if (!byFull.TryGetValue(h, out g)) { g = new DupGroup(); g.Hash = h; g.Bytes = f.Bytes; byFull[h] = g; }
                    g.Files.Add(new FileEntry(ToShort(f.Path), f.Bytes, f.LastWrite));
                    if (job != null) job.Tick(1, 0);
                }
                foreach (DupGroup g in byFull.Values) if (g.Files.Count > 1) groups.Add(g);
            }
            groups.Sort(delegate (DupGroup x, DupGroup y) { return y.Wasted.CompareTo(x.Wasted); });
            return groups;
        }

        public static Job StartDuplicates(string[] roots, long minBytes, string[] skipDirs)
        {
            return Job.Start(delegate (Job j) { return FindDuplicates(roots, minBytes, skipDirs, j); });
        }
    }
}
