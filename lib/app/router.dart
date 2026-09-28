import 'package:go_router/go_router.dart';

import '../features/dashboard/presentation/dashboard_screen.dart';
import '../features/offices/presentation/offices_screen.dart';
import '../features/projects/presentation/projects_screen.dart';
import '../features/reports/presentation/reports_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/tasks/presentation/tasks_screen.dart';
import '../features/work_logs/presentation/add_edit_entry_screen.dart';
import '../features/work_logs/presentation/work_logs_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (context, state) => const DashboardScreen()),
    GoRoute(
      path: '/add-entry',
      builder: (context, state) => const AddEditEntryScreen(),
    ),
    GoRoute(
      path: '/edit-entry/:id',
      builder: (context, state) => AddEditEntryScreen(
        entryId: int.parse(state.pathParameters['id']!),
      ),
    ),
    GoRoute(path: '/work-logs', builder: (context, state) => const WorkLogsScreen()),
    GoRoute(path: '/offices', builder: (context, state) => const OfficesScreen()),
    GoRoute(path: '/projects', builder: (context, state) => const ProjectsScreen()),
    GoRoute(path: '/tasks', builder: (context, state) => const TasksScreen()),
    GoRoute(path: '/reports', builder: (context, state) => const ReportsScreen()),
    GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
  ],
);
