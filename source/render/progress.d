module render.progress;

import std.stdio : write, writeln, stdout;
import core.atomic;

struct ProgressTracker {
    private shared int completedItems = 0;
    private shared int lastMilestone = 0;
    private int totalItems;
    private int milestoneStep;
    
    this(int total, int step = 5) {
        totalItems = total;
        milestoneStep = step;
    }
    
    void start() {
        write("Progress: 0%");
        stdout.flush();
    }
    
    void update() {
        int completed = atomicOp!"+="(completedItems, 1);
        int percent = cast(int)((cast(long)completed * 100) / totalItems);
        int milestone = percent / milestoneStep * milestoneStep;
        int oldMilestone = atomicLoad(lastMilestone);
        
        if (milestone > oldMilestone && milestone <= 100) {
            import core.atomic : cas;
            if (cas(&lastMilestone, oldMilestone, milestone)) {
                write(" ", milestone, "%");
                stdout.flush();
            }
        }
    }
    
    void finish() {
        writeln();
        stdout.flush();
    }
}

void displayColumnProgress(ref shared int completedColumns, int totalColumns, ref shared int lastMilestone) {
    int completed = atomicOp!"+="(completedColumns, 1);
    int percent = cast(int)((cast(long)completed * 100) / totalColumns);
    int milestone = percent / 5 * 5;
    int oldMilestone = atomicLoad(lastMilestone);
    
    if (milestone > oldMilestone && milestone <= 100) {
        import core.atomic : cas;
        if (cas(&lastMilestone, oldMilestone, milestone)) {
            write(" ", milestone, "%");
            stdout.flush();
        }
    }
}

